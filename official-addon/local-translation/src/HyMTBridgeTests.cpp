#include "HyMTBridge.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <mach/mach.h>
static void require(bool value, const char * label) { if (!value) { std::fprintf(stderr, "FAIL %s\n", label); std::exit(1); } }
static uint64_t footprint() {
    task_vm_info_data_t info{}; mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS ? info.phys_footprint : 0;
}
int main(int argc, char ** argv) {
    require(argc == 2 || argc == 3, "model path [threads]");
    int threads = argc == 3 ? std::atoi(argv[2]) : 4;
    require(!tio_hymt_request_new(0), "invalid timeout");
    auto load = tio_hymt_request_new(30000); int32_t status = 0;
    auto engine = tio_hymt_load(argv[1], threads, load, &status);
    tio_hymt_request_free(load);
    require(engine && status == 0, "load");
    const char * texts[] = {"前方八十米右转，到达后请停止导航。", "The next train leaves in five minutes. Please stand behind the yellow line.", "请问最近的地铁站在哪里？", "Could you speak more slowly? I am using live captions.", "会议改到明天下午三点，请带上最新的产品演示。"};
    for (int i = 0; i < 5; ++i) {
        auto r = tio_hymt_request_new(15000); char output[8192]; TIOHyMTMetrics metrics{};
        status = tio_hymt_translate(engine, r, texts[i], i % 2 ? "Chinese" : "English", 192, output, sizeof(output), &metrics);
        tio_hymt_request_free(r);
        require(status == 0 && output[0], "translation");
        std::printf("sample=%d first_ms=%.2f total_ms=%.2f prompt=%d output=%d text=%s\n", i, metrics.first_token_ms, metrics.total_ms, metrics.prompt_tokens, metrics.output_tokens, output);
    }
    char output[8192]; auto cancelled = tio_hymt_request_new(5000);
    struct Stream { std::string last; int count = 0; TIOHyMTRequest * cancel = nullptr; };
    auto callback = +[](const char * bytes, size_t length, void * context) {
        auto & stream = *static_cast<Stream *>(context);
        require(length >= stream.last.size() && std::string(bytes, stream.last.size()) == stream.last, "cumulative prefix");
        stream.last.assign(bytes, length); stream.count++;
        if (stream.cancel) tio_hymt_request_cancel(stream.cancel);
    };
    auto streaming = tio_hymt_request_new(15000); Stream stream; TIOHyMTMetrics streamedMetrics{};
    require(tio_hymt_translate_stream(engine, streaming, texts[1], "Chinese", 384, output, sizeof(output), &streamedMetrics,
        threads, callback, &stream) == 0, "stream success");
    require(stream.count >= 2 && stream.last == output && streamedMetrics.first_token_ms > 0 && streamedMetrics.total_ms >= streamedMetrics.first_token_ms, "stream final and timing");
    tio_hymt_request_free(streaming);
    auto stopStream = tio_hymt_request_new(15000); Stream stopping; stopping.cancel = stopStream;
    require(tio_hymt_translate_stream(engine, stopStream, texts[1], "Chinese", 384, output, sizeof(output), nullptr,
        threads, callback, &stopping) == TIO_HY_CANCELLED && !output[0], "cancel from partial does not finalize");
    tio_hymt_request_free(stopStream);
    auto invalid = tio_hymt_request_new(15000);
    require(tio_hymt_translate_stream(engine, invalid, texts[0], "English", 384, output, sizeof(output), nullptr, 9, nullptr, nullptr) == TIO_HY_INVALID, "thread cap");
    tio_hymt_request_free(invalid);
    tio_hymt_request_cancel(cancelled);
    require(tio_hymt_translate(engine, cancelled, texts[0], "English", 128, output, sizeof(output), nullptr) == TIO_HY_CANCELLED && !output[0], "pre-cancel");
    tio_hymt_request_free(cancelled);
    auto timeout = tio_hymt_request_new(1); std::this_thread::sleep_for(std::chrono::milliseconds(3));
    require(tio_hymt_translate(engine, timeout, texts[0], "English", 128, output, sizeof(output), nullptr) == TIO_HY_TIMEOUT && !output[0], "timeout");
    tio_hymt_request_free(timeout);
    auto limit = tio_hymt_request_new(5000);
    require(tio_hymt_translate(engine, limit, texts[0], "English", 1, output, sizeof(output), nullptr) == TIO_HY_LIMIT && !output[0], "no truncated final");
    std::string oversized(4097, 'a');
    require(tio_hymt_translate(engine, limit, oversized.c_str(), "English", 128, output, sizeof(output), nullptr) == TIO_HY_INVALID, "text capacity");
    tio_hymt_request_free(limit);
    auto running = tio_hymt_request_new(15000); std::atomic<int> running_status{-1};
    std::thread worker([&] { char out[8192]; running_status = tio_hymt_translate(engine, running, texts[1], "Chinese", 256, out, sizeof(out), nullptr); });
    std::this_thread::sleep_for(std::chrono::milliseconds(20)); tio_hymt_request_cancel(running); worker.join();
    require(running_status == TIO_HY_CANCELLED, "in-flight cancel"); tio_hymt_request_free(running);
    auto recovery = tio_hymt_request_new(10000);
    require(tio_hymt_translate(engine, recovery, texts[0], "English", 128, output, sizeof(output), nullptr) == TIO_HY_OK, "reuse after cancellation");
    tio_hymt_request_free(recovery);
    uint64_t before = footprint(), peak = before;
    for (int i = 0; i < 30; ++i) {
        auto r = tio_hymt_request_new(15000);
        require(tio_hymt_translate(engine, r, texts[i % 5], i % 5 % 2 ? "Chinese" : "English", 192, output, sizeof(output), nullptr) == TIO_HY_OK, "repeat translation");
        tio_hymt_request_free(r); peak = std::max(peak, footprint());
    }
    auto after = footprint();
    tio_hymt_free(engine);
    std::printf("repeat_count=30 threads=%d footprint_before=%llu footprint_after=%llu sampled_peak=%llu after_unload=%llu\n", threads, (unsigned long long)before, (unsigned long long)after, (unsigned long long)peak, (unsigned long long)footprint());
    std::puts("PASS translations, limits, timeout, cancellation, reuse, release");
}
