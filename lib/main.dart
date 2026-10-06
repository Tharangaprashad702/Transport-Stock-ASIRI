import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.instance.init();
  runApp(const AsiriApp());
}

String hashPassword(String s) => sha256.convert(utf8.encode(s)).toString();

class AsiriApp extends StatelessWidget {
  const AsiriApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Transport Stock ASIRI', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123B72)), useMaterial3: true),
    home: const Gate(),
  );
}

class Gate extends StatefulWidget { const Gate({super.key}); @override State<Gate> createState()=>_GateState(); }
class _GateState extends State<Gate> {
  bool? logged;
  @override void initState(){super.initState(); _check();}
  Future<void> _check() async { final p=await SharedPreferences.getInstance(); setState(()=>logged=p.getBool('logged')??false); }
  @override Widget build(BuildContext c)=>logged==null?const Scaffold(body:Center(child:CircularProgressIndicator())):logged!?const Home():const AuthPage();
}

class AuthPage extends StatefulWidget { const AuthPage({super.key}); @override State<AuthPage> createState()=>_AuthState(); }
class _AuthState extends State<AuthPage> {
  final u=TextEditingController(), p=TextEditingController(), p2=TextEditingController(); bool reg=false;
  void msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  Future<void> go() async {
    if(u.text.trim().isEmpty||p.text.isEmpty){msg('Enter username and password');return;}
    if(reg){
      if(p.text!=p2.text){msg('Passwords do not match');return;}
      if(await AppDb.instance.hasUsers()){msg('A user already exists. Login instead.');return;}
      await AppDb.instance.createUser(u.text.trim(),hashPassword(p.text));
    } else if(!await AppDb.instance.login(u.text.trim(),hashPassword(p.text))){msg('Invalid login');return;}
    final sp=await SharedPreferences.getInstance(); await sp.setBool('logged',true);
    if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const Home()));
  }
  @override Widget build(BuildContext c)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(children:[
    Image.asset('assets/asiri_logo.png',height:170), Text(reg?'REGISTER':'LOGIN',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:14), TextField(controller:u,decoration:const InputDecoration(labelText:'Username',border:OutlineInputBorder())),
    const SizedBox(height:10), TextField(controller:p,obscureText:true,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),
    if(reg) ...[const SizedBox(height:10),TextField(controller:p2,obscureText:true,decoration:const InputDecoration(labelText:'Confirm password',border:OutlineInputBorder()))],
    const SizedBox(height:14),FilledButton(onPressed:go,child:Text(reg?'CREATE ACCOUNT':'LOGIN')),
    TextButton(onPressed:()=>setState(()=>reg=!reg),child:Text(reg?'Login':'Register first'))
  ])));
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home>{
  int tab=0;
  final pages=const [Dashboard(),PartsPage(),StockInPage(),ScanOutPage(),HistoryPage(),ReportsPage()];
  @override Widget build(BuildContext c)=>Scaffold(
    appBar:AppBar(title:const Text('TRANSPORT STOCK ASIRI',style:TextStyle(fontWeight:FontWeight.bold)),actions:[
      IconButton(onPressed:()async{final sp=await SharedPreferences.getInstance();await sp.setBool('logged',false);if(mounted)Navigator.pushReplacement(c,MaterialPageRoute(builder:(_)=>const AuthPage()));},icon:const Icon(Icons.logout))
    ]),
    body:pages[tab],
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
      NavigationDestination(icon:Icon(Icons.dashboard),label:'Home'),
      NavigationDestination(icon:Icon(Icons.inventory_2),label:'Parts'),
      NavigationDestination(icon:Icon(Icons.add_box),label:'IN'),
      NavigationDestination(icon:Icon(Icons.qr_code_scanner),label:'OUT'),
      NavigationDestination(icon:Icon(Icons.history),label:'History'),
      NavigationDestination(icon:Icon(Icons.bar_chart),label:'Reports'),
    ]));
}

class Dashboard extends StatelessWidget { const Dashboard({super.key});
  @override Widget build(BuildContext c)=>FutureBuilder(future:AppDb.instance.summary(),builder:(c,s){
    final x=s.data??{'parts':0,'stock':0,'in':0,'out':0,'low':0};
    return ListView(padding:const EdgeInsets.all(14),children:[
      Image.asset('assets/asiri_logo.png',height:170),
      Wrap(spacing:8,runSpacing:8,children:[card('Parts',x['parts']!,Icons.build),card('Stock',x['stock']!,Icons.inventory),card('IN',x['in']!,Icons.arrow_downward),card('OUT',x['out']!,Icons.arrow_upward),card('Low',x['low']!,Icons.warning_amber)]),
      const SizedBox(height:15),const Text('QR OUT: scan a part QR to reduce its balance. IN: select a part and add received stock.',style:TextStyle(fontSize:16))
    ]); }
  static Widget card(String t,int v,IconData i)=>SizedBox(width:155,child:Card(child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[Icon(i),const SizedBox(width:7),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t),Text('$v',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold))])]))));
}

class PartsPage extends StatefulWidget { const PartsPage({super.key}); @override State<PartsPage> createState()=>_PartsState(); }
class _PartsState extends State<PartsPage>{
  final q=TextEditingController();
  @override Widget build(BuildContext c)=>Column(children:[
    Padding(padding:const EdgeInsets.all(10),child:TextField(controller:q,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search spare part',border:OutlineInputBorder()))),
    Expanded(child:FutureBuilder(future:AppDb.instance.parts(q.text),builder:(c,s){
      final ps=s.data??[]; return ListView.builder(itemCount:ps.length,itemBuilder:(c,i){
        final p=ps[i]; return ListTile(leading:CircleAvatar(child:Text('${p['balance']}')),title:Text('${p['name']}'),subtitle:Text('${p['code']} • IN ${p['in_qty']} • OUT ${p['out_qty']} • Balance ${p['balance']}'),
          trailing:PopupMenuButton<String>(onSelected:(v)async{
            if(v=='qr')Navigator.push(c,MaterialPageRoute(builder:(_)=>QrPage(part:p)));
            if(v=='edit')await Navigator.push(c,MaterialPageRoute(builder:(_)=>EditPage(part:p)));
            if(v=='delete'){await AppDb.instance.deletePart(p['id']);setState((){});}
          },itemBuilder:(_)=>const[PopupMenuItem(value:'qr',child:Text('QR / Print')),PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete'))]));
      });
    }))
  ]);
}

class AddPartForm extends StatefulWidget { const AddPartForm({super.key}); @override State<AddPartForm> createState()=>_AddState(); }
class _AddState extends State<AddPartForm>{
  final n=TextEditingController(),code=TextEditingController(),qty=TextEditingController(text:'0'),low=TextEditingController(text:'5');
  Future<void> save()async{
    if(n.text.trim().isEmpty)return; final id='ASIRI-${DateTime.now().millisecondsSinceEpoch}';
    try{await AppDb.instance.addPart(id:id,name:n.text.trim(),code:code.text.trim().isEmpty?id:code.text.trim(),qty:int.tryParse(qty.text)??0,lowLimit:int.tryParse(low.text)??5);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Part added. Unique QR created.')));n.clear();code.clear();qty.text='0';
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Error: $e')));}
  }
  @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ADD SPARE PART',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:15),
    TextField(controller:n,decoration:const InputDecoration(labelText:'Part name',border:OutlineInputBorder())),const SizedBox(height:10),
    TextField(controller:code,decoration:const InputDecoration(labelText:'Part number / code (optional)',border:OutlineInputBorder())),const SizedBox(height:10),
    TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Initial IN quantity',border:OutlineInputBorder())),const SizedBox(height:10),
    TextField(controller:low,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Low-stock limit',border:OutlineInputBorder())),const SizedBox(height:15),
    FilledButton.icon(onPressed:save,icon:const Icon(Icons.qr_code_2),label:const Text('ADD + CREATE QR'))
  ]);
}
class StockInPage extends StatefulWidget { const StockInPage({super.key}); @override State<StockInPage> createState()=>_InState(); }
class _InState extends State<StockInPage>{
  String? id; final qty=TextEditingController(text:'1'),note=TextEditingController();
  @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('STOCK IN',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:15),
    FutureBuilder(future:AppDb.instance.parts(''),builder:(c,s)=>DropdownButtonFormField<String>(value:id,decoration:const InputDecoration(labelText:'Spare part',border:OutlineInputBorder()),
      items:(s.data??[]).map<DropdownMenuItem<String>>((p)=>DropdownMenuItem(value:p['id'].toString(),child:Text(p['name'].toString()))).toList(),onChanged:(v)=>setState(()=>id=v))),
    const SizedBox(height:10),TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Quantity IN',border:OutlineInputBorder())),const SizedBox(height:10),
    TextField(controller:note,decoration:const InputDecoration(labelText:'Supplier / note',border:OutlineInputBorder())),const SizedBox(height:15),
    FilledButton(onPressed:()async{if(id==null)return;final ok=await AppDb.instance.addStock(id!,int.tryParse(qty.text)??0,note.text);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?'Stock added':'Could not add stock')));},child:const Text('ADD STOCK'))
  ]);
}

class ScanOutPage extends StatefulWidget { const ScanOutPage({super.key}); @override State<ScanOutPage> createState()=>_ScanState(); }
class _ScanState extends State<ScanOutPage>{
  bool busy=false;
  Future<void> scan(String raw)async{
    if(busy||!raw.startsWith('ASIRI|'))return; busy=true;
    final id=raw.substring(6), p=await AppDb.instance.getPart(id);
    if(p==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Unknown QR')));busy=false;return;}
    final qty=await showDialog<int>(context:context,builder:(_)=>const QtyDialog());
    if(qty!=null){final r=await AppDb.instance.stockOut(id,qty,'QR sale / OUT');ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(r==null?'Not enough stock':'${p['name']} OUT $qty • Balance ${r['balance']}')));}
    await Future.delayed(const Duration(milliseconds:700));busy=false;
  }
  @override Widget build(BuildContext c)=>Stack(children:[MobileScanner(onDetect:(cap){for(final b in cap.barcodes){final v=b.rawValue;if(v!=null)scan(v);}}),const Center(child:Icon(Icons.crop_free,size:260,color:Colors.white70))]);
}
class QtyDialog extends StatefulWidget { const QtyDialog({super.key}); @override State<QtyDialog> createState()=>_QtyState(); }
class _QtyState extends State<QtyDialog>{final q=TextEditingController(text:'1');@override Widget build(BuildContext c)=>AlertDialog(title:const Text('OUT quantity'),content:TextField(controller:q,keyboardType:TextInputType.number),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,int.tryParse(q.text)??1),child:const Text('OUT'))]);}

class QrPage extends StatelessWidget { final Map<String,dynamic> part; const QrPage({super.key,required this.part});
  Future<Uint8List> pdf(Map<String,dynamic> p,String data)async{final d=pw.Document();d.addPage(pw.Page(build:(_)=>pw.Center(child:pw.Column(mainAxisAlignment:pw.MainAxisAlignment.center,children:[pw.BarcodeWidget(barcode:pw.Barcode.qrCode(),data:data,width:250,height:250),pw.SizedBox(height:12),pw.Text(p['name'],style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold)),pw.Text('Code: ${p['code']}')]))));return d.save();}
  @override Widget build(BuildContext c){final data='ASIRI|${part['id']}';return Scaffold(appBar:AppBar(title:Text(part['name'])),body:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[QrImageView(data:data,size:290),Text(part['name'],style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text('Code: ${part['code']}'),const SizedBox(height:15),FilledButton.icon(onPressed:()=>Printing.layoutPdf(onLayout:(_)=>pdf(part,data)),icon:const Icon(Icons.print),label:const Text('PRINT QR LABEL')),OutlinedButton.icon(onPressed:()=>Share.share('TRANSPORT STOCK ASIRI\n${part['name']}\nCode: ${part['code']}\nQR: $data'),icon:const Icon(Icons.share),label:const Text('SHARE QR INFO'))])));}
}

class EditPage extends StatefulWidget { final Map<String,dynamic> part; const EditPage({super.key,required this.part}); @override State<EditPage> createState()=>_EditState(); }
class _EditState extends State<EditPage>{late TextEditingController n,code,low;@override void initState(){super.initState();n=TextEditingController(text:widget.part['name']);code=TextEditingController(text:widget.part['code']);low=TextEditingController(text:'${widget.part['low_limit']}');}
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Edit Part')),body:ListView(padding:const EdgeInsets.all(16),children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Part name')),TextField(controller:code,decoration:const InputDecoration(labelText:'Code')),TextField(controller:low,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Low limit')),const SizedBox(height:15),FilledButton(onPressed:()async{await AppDb.instance.editPart(widget.part['id'],n.text,code.text,int.tryParse(low.text)??5);if(mounted)Navigator.pop(c);},child:const Text('SAVE'))]));}

class HistoryPage extends StatelessWidget { const HistoryPage({super.key}); @override Widget build(BuildContext c)=>FutureBuilder(future:AppDb.instance.movements(),builder:(c,s){final m=s.data??[];return ListView.builder(itemCount:m.length,itemBuilder:(c,i){final x=m[i];return ListTile(leading:CircleAvatar(child:Text(x['type'])),title:Text('${x['name']} • ${x['type']} ${x['qty']}'),subtitle:Text('${x['code']}\n${x['created_at']}'),isThreeLine:true);});});}

class ReportsPage extends StatelessWidget { const ReportsPage({super.key});
  Future<void> csvReport()async{final ps=await AppDb.instance.parts('');final rows=[['Part','Code','IN','OUT','Balance','Low Limit'],...ps.map((p)=>[p['name'],p['code'],p['in_qty'],p['out_qty'],p['balance'],p['low_limit']])];final csv=const ListToCsvConverter().convert(rows);final d=await getTemporaryDirectory();final f=File('${d.path}/transport_stock_asiri.csv');await f.writeAsString(csv);await Share.shareXFiles([XFile(f.path)],text:'ASIRI CSV report');}
  Future<void> pdfReport()async{final ps=await AppDb.instance.parts('');final d=pw.Document();d.addPage(pw.MultiPage(build:(_)=>[pw.Text('TRANSPORT STOCK ASIRI',style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:12),pw.Table.fromTextArray(data:[['Part','Code','IN','OUT','Balance'],...ps.map((p)=>[p['name'],p['code'],'${p['in_qty']}','${p['out_qty']}','${p['balance']}'])]) ]));await Printing.layoutPdf(onLayout:(_)=>d.save());}
  Future<void> backup()async{final data=await AppDb.instance.exportJson();final d=await getTemporaryDirectory();final f=File('${d.path}/transport_stock_asiri_backup.json');await f.writeAsString(data);await Share.shareXFiles([XFile(f.path)],text:'ASIRI backup');}
  @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[const Text('REPORTS & BACKUP',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:15),FilledButton.icon(onPressed:csvReport,icon:const Icon(Icons.table_view),label:const Text('EXPORT CSV')),FilledButton.icon(onPressed:pdfReport,icon:const Icon(Icons.picture_as_pdf),label:const Text('PRINT / PDF REPORT')),FilledButton.icon(onPressed:backup,icon:const Icon(Icons.backup),label:const Text('BACKUP DATA')),const SizedBox(height:10),const Text('For true multi-phone cloud sync, a secure cloud database/API should be connected in the production version.')]);
}
