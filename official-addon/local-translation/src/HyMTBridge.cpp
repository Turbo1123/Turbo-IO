#include "HyMTBridge.h"
#include "llama.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;
struct TIOHyMTRequest {
    std::atomic<bool> cancelled{false};
    Clock::time_point deadline;
    explicit TIOHyMTRequest(int ms) : deadline(Clock::now() + std::chrono::milliseconds(ms)) {}
};
struct TIOHyMT {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    std::mutex mutex;
    ~TIOHyMT() { if (context) llama_free(context); if (model) llama_model_free(model); }
};
static int stopped(TIOHyMTRequest * r) {
    if (r->cancelled.load()) return TIO_HY_CANCELLED;
    return Clock::now() >= r->deadline ? TIO_HY_TIMEOUT : TIO_HY_OK;
}
static bool abort_decode(void * p) { return stopped(static_cast<TIOHyMTRequest *>(p)) != 0; }
static bool load_progress(float, void * p) { return !abort_decode(p); }
static void quiet_log(enum ggml_log_level, const char *, void *) {} // No transcript/path logging in host.
static double elapsed(Clock::time_point start) { return std::chrono::duration<double, std::milli>(Clock::now() - start).count(); }
TIOHyMTRequest * tio_hymt_request_new(int32_t ms) {
    if (ms < 1 || ms > 120000) return nullptr;
    try { return new TIOHyMTRequest(ms); } catch (...) { return nullptr; }
}
void tio_hymt_request_cancel(TIOHyMTRequest * r) { if (r) r->cancelled.store(true); }
void tio_hymt_request_free(TIOHyMTRequest * r) { delete r; }
void tio_hymt_free(TIOHyMT * e) { delete e; }
TIOHyMT * tio_hymt_load(const char * path, int32_t threads, TIOHyMTRequest * r, int32_t * status) {
    if (!status) return nullptr;
    *status = TIO_HY_INVALID;
    if (!path || !path[0] || !r || threads < 1 || threads > 8) return nullptr;
    if ((*status = stopped(r))) return nullptr;
    try {
        static std::once_flag once;
        std::call_once(once, [] { llama_log_set(quiet_log, nullptr); llama_backend_init(); ggml_backend_load_all(); });
        auto e = std::make_unique<TIOHyMT>();
        auto mp = llama_model_default_params();
        mp.n_gpu_layers = 0;
        mp.progress_callback = load_progress; mp.progress_callback_user_data = r;
        e->model = llama_model_load_from_file(path, mp);
        if ((*status = stopped(r))) return nullptr;
        if (!e->model) { *status = TIO_HY_LOAD; return nullptr; }
        char architecture[64] = {};
        llama_model_meta_val_str(e->model, "general.architecture", architecture, sizeof(architecture));
        if (std::strcmp(architecture, "hunyuan-dense") || llama_model_n_embd(e->model) != 2048 || llama_model_n_layer(e->model) != 32) {
            *status = TIO_HY_INVALID; return nullptr;
        }
        auto cp = llama_context_default_params();
        cp.n_ctx = 1024; cp.n_batch = 128; cp.n_ubatch = 128; cp.n_seq_max = 1;
        cp.n_threads = threads; cp.n_threads_batch = threads;
        cp.offload_kqv = false; cp.op_offload = false;
        cp.abort_callback = abort_decode; cp.abort_callback_data = r;
        e->context = llama_init_from_model(e->model, cp);
        if ((*status = stopped(r))) return nullptr;
        if (!e->context) { *status = TIO_HY_CONTEXT; return nullptr; }
        // Loading request is released by caller; never retain its pointer in context.
        llama_set_abort_callback(e->context, nullptr, nullptr);
        *status = TIO_HY_OK; return e.release();
    } catch (...) { *status = TIO_HY_LOAD; return nullptr; }
}
static bool append_tokens(const llama_vocab * vocab, const std::string & text, bool special, std::vector<llama_token> & out) {
    int n = llama_tokenize(vocab, text.data(), (int)text.size(), nullptr, 0, false, special);
    if (n >= 0 || -n > 1024) return false;
    std::vector<llama_token> part(-n);
    n = llama_tokenize(vocab, text.data(), (int)text.size(), part.data(), (int)part.size(), false, special);
    if (n < 0) return false;
    out.insert(out.end(), part.begin(), part.begin() + n); return true;
}
int32_t tio_hymt_translate(TIOHyMT * e, TIOHyMTRequest * r, const char * text, const char * language,
                          int32_t max_tokens, char * output, size_t capacity, TIOHyMTMetrics * metrics) {
    return tio_hymt_translate_stream(e, r, text, language, max_tokens, output, capacity, metrics, 0, nullptr, nullptr);
}
int32_t tio_hymt_translate_stream(TIOHyMT * e, TIOHyMTRequest * r, const char * text, const char * language,
                          int32_t max_tokens, char * output, size_t capacity, TIOHyMTMetrics * metrics,
                          int32_t threads, TIOHyMTPartial partial, void *context) {
    if (output && capacity) output[0] = 0;
    if (metrics) *metrics = {};
    if (!e || !r || !text || !language || !output || capacity < 2 || capacity > 16384 || max_tokens < 1 || max_tokens > 512 || threads < 0 || threads > 8) return TIO_HY_INVALID;
    size_t length = strnlen(text, 4097), lang_length = strnlen(language, 65);
    if (!length || length > 4096 || !lang_length || lang_length > 64) return TIO_HY_INVALID;
    for (size_t i = 0; i < lang_length; ++i) if (!((language[i] >= 'A' && language[i] <= 'Z') || (language[i] >= 'a' && language[i] <= 'z') || language[i] == ' ' || language[i] == '-')) return TIO_HY_INVALID;
    std::unique_lock<std::mutex> lock(e->mutex, std::try_to_lock);
    if (!lock.owns_lock()) return TIO_HY_BUSY;
    if (threads) llama_set_n_threads(e->context, threads, threads);
    if (int s = stopped(r)) return s;
    const auto start = Clock::now();
    struct Cleanup {
        TIOHyMT * e; TIOHyMTMetrics * metrics; Clock::time_point start;
        ~Cleanup() { llama_set_abort_callback(e->context, nullptr, nullptr); llama_memory_clear(llama_get_memory(e->context), true); if (metrics) metrics->total_ms = elapsed(start); }
    } cleanup{e, metrics, start};
    try {
        llama_memory_clear(llama_get_memory(e->context), true);
        llama_set_abort_callback(e->context, abort_decode, r);
        auto vocab = llama_model_get_vocab(e->model);
        // Exact single-turn template from pinned GGUF; user text is NEVER parsed as special tokens.
        std::vector<llama_token> tokens;
        const std::string instruction = "Translate the following text into " + std::string(language) + ". Note that you should only output the translated result without any additional explanation:\n" + text;
        if (!append_tokens(vocab, "<｜hy_begin▁of▁sentence｜><｜hy_User｜>", true, tokens) ||
            !append_tokens(vocab, instruction, false, tokens) || !append_tokens(vocab, "<｜hy_Assistant｜>", true, tokens)) return TIO_HY_LIMIT;
        if (tokens.size() + max_tokens > 1024) return TIO_HY_LIMIT;
        if (metrics) metrics->prompt_tokens = (int32_t)tokens.size();
        for (size_t i = 0; i < tokens.size(); i += 128) {
            if (int s = stopped(r)) return s;
            auto batch = llama_batch_get_one(tokens.data() + i, (int32_t)std::min<size_t>(128, tokens.size() - i));
            int rc = llama_decode(e->context, batch);
            if (int s = stopped(r)) return s;
            if (rc) return TIO_HY_DECODE;
        }
        std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(llama_sampler_init_greedy(), llama_sampler_free);
        if (!sampler) return TIO_HY_CONTEXT;
        std::string result;
        auto published = start - std::chrono::seconds(1);
        for (int i = 0; i < max_tokens; ++i) {
            if (int s = stopped(r)) return s;
            auto token = llama_sampler_sample(sampler.get(), e->context, -1);
            if (llama_vocab_is_eog(vocab, token)) {
                if (result.empty()) return TIO_HY_DECODE;
                if (partial) partial(result.data(), result.size(), context);
                if (int s = stopped(r)) return s;
                std::memcpy(output, result.c_str(), result.size() + 1); return TIO_HY_OK;
            }
            char piece[1024];
            int n = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, false);
            if (n < 0 || result.size() + n >= capacity) return TIO_HY_LIMIT;
            result.append(piece, n);
            if (metrics) { metrics->output_tokens = i + 1; if (i == 0) metrics->first_token_ms = elapsed(start); }
            if (partial && Clock::now() - published >= std::chrono::milliseconds(60)) {
                partial(result.data(), result.size(), context); published = Clock::now();
            }
            auto batch = llama_batch_get_one(&token, 1);
            int rc = llama_decode(e->context, batch);
            if (int s = stopped(r)) return s;
            if (rc) return TIO_HY_DECODE;
        }
        return TIO_HY_LIMIT;
    } catch (...) { return TIO_HY_DECODE; }
}
