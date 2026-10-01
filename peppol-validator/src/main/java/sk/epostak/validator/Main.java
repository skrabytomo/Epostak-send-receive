package sk.epostak.validator;

import java.io.File;
import java.util.Locale;
import org.w3c.dom.Document;
import com.helger.diver.api.coord.DVRCoordinate;
import com.helger.phive.api.executorset.IValidationExecutorSet;
import com.helger.phive.api.executorset.ValidationExecutorSetRegistry;
import com.helger.phive.api.result.ValidationResultList;
import com.helger.phive.api.validity.IValidityDeterminator;
import com.helger.phive.peppol.pint.PeppolValidationPint;
import com.helger.phive.peppol.pint.PeppolValidationPintEU;
import com.helger.phive.xml.source.IValidationSourceXML;
import com.helger.phive.xml.source.ValidationSourceXML;
import com.helger.xml.serialize.read.DOMReader;

public final class Main {
  private Main() {}
  private static String jsonEscape(String s) {
    if (s == null) return "";
    StringBuilder b = new StringBuilder(s.length() + 16);
    for (int i=0;i<s.length();i++) {
      char c=s.charAt(i);
      switch(c) {
        case '\\': b.append("\\\\"); break;
        case '"': b.append("\\\""); break;
        case '\n': b.append("\\n"); break;
        case '\r': b.append("\\r"); break;
        case '\t': b.append("\\t"); break;
        default: if(c<0x20)b.append(String.format("\\u%04x",(int)c)); else b.append(c);
      }
    }
    return b.toString();
  }
  public static void main(String[] args) {
    try {
      if(args.length!=2){System.err.println("Usage: java -jar EpostakPeppolValidator.jar <invoice|creditnote|auto> <xml-file>");System.exit(2);}
      String type=args[0].trim().toLowerCase(Locale.ROOT);
      File file=new File(args[1]);
      if(!file.isFile()){System.err.println("XML_FILE_NOT_FOUND");System.exit(3);}
      Document doc=DOMReader.readXMLDOM(file);
      if(doc==null||doc.getDocumentElement()==null){System.err.println("XML_PARSE_ERROR");System.exit(4);}
      String root=doc.getDocumentElement().getLocalName();
      if(root==null||root.isEmpty()){root=doc.getDocumentElement().getNodeName();int p=root.indexOf(':');if(p>=0)root=root.substring(p+1);}
      if(!"invoice".equals(type)&&!"creditnote".equals(type)&&!"auto".equals(type)){System.err.println("INVALID_TYPE");System.exit(2);}
      if(!"Invoice".equalsIgnoreCase(root)&&!"CreditNote".equalsIgnoreCase(root)){System.err.println("UNSUPPORTED_DOCUMENT_ROOT="+root);System.exit(5);}
      boolean creditNote="creditnote".equals(type)||("auto".equals(type)&&"CreditNote".equalsIgnoreCase(root));
      ValidationExecutorSetRegistry<IValidationSourceXML> registry=new ValidationExecutorSetRegistry<>();
      PeppolValidationPint.initPeppolPint(registry);
      DVRCoordinate vesId=creditNote?PeppolValidationPintEU.VID_OPENPEPPOL_EU_PINT_CREDIT_NOTE_2026_6:PeppolValidationPintEU.VID_OPENPEPPOL_EU_PINT_INVOICE_2026_6;
      IValidationExecutorSet<IValidationSourceXML> ves=registry.getOfID(vesId);
      if(ves==null){System.err.println("VES_NOT_FOUND="+vesId.getAsString());System.exit(6);}
      ValidationSourceXML source=ValidationSourceXML.create(file.getAbsolutePath(),doc);
      ValidationResultList result=com.helger.phive.api.execute.ValidationExecutionManager.executeValidation(IValidityDeterminator.createDefault(),ves,source);
      boolean valid=result.containsNoError();
      StringBuilder out=new StringBuilder(4096);
      out.append("{\"valid\":").append(valid).append(",\"ves\":\"").append(jsonEscape(vesId.getAsString())).append("\",\"errorCount\":").append(result.getAllErrors().size()).append(",\"errors\":[");
      boolean first=true;
      for(var error:result.getAllErrors()){if(!first)out.append(',');first=false;out.append("{\"message\":\"").append(jsonEscape(error.getErrorText(Locale.US))).append("\"}");}
      out.append("]}");
      System.out.println(out);
      System.exit(valid?0:10);
    } catch(Exception e) {System.err.println("VALIDATOR_EXCEPTION="+e.getClass().getName()+": "+e.getMessage());System.exit(20);}
  }
}