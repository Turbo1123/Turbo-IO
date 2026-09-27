import com.turboio.addon.TransferGate;
import static com.turboio.addon.TransferGate.State.*;
public class TransferGateTest {
    static int count;static void check(boolean b){count++;if(!b)throw new AssertionError(count);}
    static TransferGate gate(){TransferGate g=new TransferGate();g.begin("peer","turbo-focus.tfp",42,9,100,1000);return g;}
    public static void main(String[] args){
        TransferGate g=gate();check(g.state()==SUBMITTING);check(!g.mayDeleteSpool());
        check(g.acknowledgement("peer",42,9,0));check(g.state()==SUBMITTING);
        g.submitted("native");check(g.state()==WAITING);
        check(!g.fileResult("other","native","turbo-focus.tfp",true,true));
        check(!g.fileResult("peer","wrong","turbo-focus.tfp",true,true));
        check(!g.fileResult("peer","native","turbo-app.tax",true,true));
        check(!g.fileResult("peer","native","turbo-focus.tfp",false,true));
        check(g.fileResult("peer","native","turbo-focus.tfp",true,true));check(g.state()==CONFIRMED);check(g.mayDeleteSpool());
        check(!g.acknowledgement("peer",42,9,4));check(g.state()==CONFIRMED);
        g=gate();g.submitted("native");g.fileResult("peer","native","turbo-focus.tfp",true,true);check(g.state()==WAITING);
        check(!g.acknowledgement("peer",41,9,0));check(!g.acknowledgement("peer",42,8,0));
        check(g.acknowledgement("peer",42,9,4));check(g.state()==REJECTED&&g.result()==4);
        g=gate();g.submitted("native");g.tick("peer",1100);check(g.state()==UNCERTAIN);check(!g.mayDeleteSpool());
        check(!g.fileResult("peer","native","turbo-focus.tfp",true,true));
        g=gate();g.tick("other",101);check(g.state()==UNCERTAIN);
        g=gate();g.submitted(null);check(g.state()==UNCERTAIN);
        g=gate();g.submitted("native");g.submitted("different");check(g.state()==UNCERTAIN);
        g=gate();g.acknowledgement("peer",42,9,0);g.acknowledgement("peer",42,9,1);check(g.state()==UNCERTAIN);
        g=gate();g.submitted("native");g.fileResult("peer","native","turbo-focus.tfp",true,false);check(g.state()==FAILED&&!g.mayDeleteSpool());
        boolean rejected=false;g=gate();try{g.begin("peer","turbo-app.tax",43,0,0,100);}catch(IllegalStateException e){rejected=true;}check(rejected);
        System.out.println("Transfer gate: "+count+" assertions passed");
    }
}
