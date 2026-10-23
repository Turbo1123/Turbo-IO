import com.turboio.addon.ChatPolicy;
public final class ChatPolicyTest {
    private static int checks;
    private static void check(boolean value) { if (!value) throw new AssertionError("check " + checks); checks++; }
    public static void main(String[] args) {
        check(ChatPolicy.eligible("chat","chat","workflow",false,false));
        check(!ChatPolicy.eligible("task","create_task","workflow",false,true));
        check(!ChatPolicy.eligible("chat","chat","workflow",true,false));
        check(!ChatPolicy.eligible("chat","chat","workflow",false,true));
        check(!ChatPolicy.eligible("chat","chat","unknown",false,false));
        check(ChatPolicy.endpoint("https://api.example.com/v1/chat/completions"));
        check(!ChatPolicy.endpoint("http://api.example.com/chat/completions"));
        check(!ChatPolicy.endpoint("https://user:pass@api.example.com/chat/completions"));
        check(!ChatPolicy.endpoint("https://api.example.com/chat/completions?key=x"));
        check(!ChatPolicy.endpoint("https://api.example.com/chat/completions#x"));
        check("香港".equals(ChatPolicy.delta("介绍", "介绍香港")));
        check(ChatPolicy.delta("介绍香港", "香港") == null);
        check("香港".equals(ChatPolicy.delta("", "香港")));
        ChatPolicy.History history = new ChatPolicy.History();
        for(int i=0;i<40;i++) history.append("q"+i,"a"+i);
        check(history.snapshot().size()==50); check(history.snapshot().get(0)[1].equals("q15"));
        history.snapshot().get(0)[1]="mutated"; check(history.snapshot().get(0)[1].equals("q15"));
        history.append("", "empty"); check(history.snapshot().size()==50);
        history.clear(); check(history.snapshot().isEmpty());
        // DeepSeek thinking switch: installs without the pref keep the old behaviour (always disabled).
        check(ChatPolicy.thinkingDisabled(null)); check(ChatPolicy.thinkingDisabled(Boolean.TRUE)); check(!ChatPolicy.thinkingDisabled(Boolean.FALSE));
        System.out.println("PASS " + checks + " policy checks");
    }
}
