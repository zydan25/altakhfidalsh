import 'package:flutter/material.dart';
import 'customer_flow.dart';
import 'app_state.dart';
import 'shein_ui.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';


Future<void> main()async{
  WidgetsFlutterBinding.ensureInitialized();
  await api.restore();
  await state.restorePreferences();
  runApp(const AltakhfidApp());
}

class AltakhfidApp extends StatelessWidget{
  const AltakhfidApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'التخفيض الصح',
    theme:ClientTheme.theme(),
    locale:const Locale('ar'),
    home:state.loggedIn?const SxAppShell():const SxAuthScreen(),
  );
}

class AppShell extends StatefulWidget{
  const AppShell({super.key});
  @override State<AppShell> createState()=>_AppShellState();
}
class _AppShellState extends State<AppShell>{
  int index=0;
  final screens=const[
    HomeScreen(),
    CategoryHubScreen(),
    LooksScreen(),
    CartScreen(),
    AccountScreen(),
  ];
  @override Widget build(BuildContext context)=>Directionality(
    textDirection:TextDirection.rtl,
    child:Scaffold(
      body:IndexedStack(index:index,children:screens),
      bottomNavigationBar:NavigationBar(
        height:62,
        backgroundColor:Colors.white,
        indicatorColor:Colors.transparent,
        selectedIndex:index,
        onDestinationSelected:(v)=>setState(()=>index=v),
        destinations:const[
          NavigationDestination(icon:Icon(Icons.home_outlined,size:21),selectedIcon:Icon(Icons.home,size:21),label:'الرئيسية'),
          NavigationDestination(icon:Icon(Icons.grid_view_outlined,size:21),selectedIcon:Icon(Icons.grid_view,size:21),label:'الفئات'),
          NavigationDestination(icon:Icon(Icons.auto_awesome_outlined,size:21),selectedIcon:Icon(Icons.auto_awesome,size:21),label:'الإطلالات'),
          NavigationDestination(icon:Icon(Icons.shopping_bag_outlined,size:21),selectedIcon:Icon(Icons.shopping_bag,size:21),label:'السلة'),
          NavigationDestination(icon:Icon(Icons.person_outline,size:21),selectedIcon:Icon(Icons.person,size:21),label:'حسابي'),
        ],
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget{
  const AuthScreen({super.key});
  @override State<AuthScreen> createState()=>_AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen>{
  final phone=TextEditingController();
  bool busy=false;
  Future<void> send()async{
    if(phone.text.trim().isEmpty)return;
    setState(()=>busy=true);
    try{
      final r=await api.requestOtp(phone.text.trim());
      if(!mounted)return;
      Navigator.push(context,MaterialPageRoute(builder:(_)=>OtpScreen(
        requestId:int.tryParse((r['otp_request_id']??0).toString())??0,
        phone:phone.text.trim(),
      )));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    }
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Directionality(
    textDirection:TextDirection.rtl,
    child:Scaffold(
      backgroundColor:Colors.white,
      body:SafeArea(child:Padding(
        padding:const EdgeInsets.all(24),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Spacer(),
          const Text('التخفيض الصح',textAlign:TextAlign.center,style:TextStyle(fontSize:30,fontWeight:FontWeight.w900)),
          const SizedBox(height:8),
          const Text('تسوق أسرع، عروض أكثر، وكل شيء في مكان واحد.',textAlign:TextAlign.center,style:TextStyle(color:ClientTheme.muted,fontSize:12)),
          const SizedBox(height:36),
          const Text('الدخول برقم الهاتف',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
          const SizedBox(height:10),
          TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(prefixText:'+967 ',hintText:'7XXXXXXXX')),
          const SizedBox(height:12),
          SizedBox(height:50,child:FilledButton(
            onPressed:busy?null:send,
            style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),
            child:busy?const CircularProgressIndicator(color:Colors.white):const Text('إرسال رمز التحقق'),
          )),
          const SizedBox(height:12),
          const Text('سيصلك الرمز عبر WhatsApp.',textAlign:TextAlign.center,style:TextStyle(color:ClientTheme.muted,fontSize:11)),
          const Spacer(),
        ]),
      )),
    ),
  );
}

class OtpScreen extends StatefulWidget{
  final int requestId;
  final String phone;
  const OtpScreen({super.key,required this.requestId,required this.phone});
  @override State<OtpScreen> createState()=>_OtpScreenState();
}
class _OtpScreenState extends State<OtpScreen>{
  final code=TextEditingController();
  bool busy=false;
  Future<void> verify()async{
    setState(()=>busy=true);
    try{
      await api.verifyOtp(widget.requestId,code.text.trim(),phone:widget.phone);
      if(!mounted)return;
      Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const AppShell()),(_)=>false);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    }
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Directionality(
    textDirection:TextDirection.rtl,
    child:Scaffold(
      appBar:AppBar(title:const Text('التحقق')),
      body:Padding(
        padding:const EdgeInsets.all(20),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const SizedBox(height:20),
          const Text('أدخل رمز التحقق',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
          const SizedBox(height:6),
          Text('تم الإرسال إلى '+widget.phone,style:const TextStyle(color:ClientTheme.muted)),
          const SizedBox(height:18),
          TextField(controller:code,maxLength:6,keyboardType:TextInputType.number,textAlign:TextAlign.center,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900,letterSpacing:7)),
          const SizedBox(height:10),
          SizedBox(height:50,child:FilledButton(
            onPressed:busy?null:verify,
            style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),
            child:busy?const CircularProgressIndicator(color:Colors.white):const Text('تأكيد الدخول'),
          )),
        ]),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget{
  const HomeScreen({super.key});
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen>{
  List<CategoryModel> roots=[];
  List<Map<String,dynamic>> side=[];
  List<ProductModel> products=[];
  List<Map<String,dynamic>> banners=[];
  List<Map<String,dynamic>> looks=[];
  List<Map<String,dynamic>> trends=[];
  int? selectedRoot;
  bool loading=true;

  @override void initState(){
    super.initState();
    load();
  }

  Future<void> load()async{
    if(mounted)setState(()=>loading=true);
    try{
      final home=await api.home();
      roots=(await api.roots());
      side=((home['side_categories'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      banners=((home['banners'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      looks=((home['looks'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      trends=((home['trends'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      products=await api.feed(category:selectedRoot);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
    }
    if(mounted)setState(()=>loading=false);
  }

  void openBanner(Map<String,dynamic> banner){
    Navigator.push(context,MaterialPageRoute(builder:(_)=>BannerLandingScreen(banner:banner)));
  }

  @override Widget build(BuildContext context)=>Directionality(
    textDirection:TextDirection.rtl,
    child:RefreshIndicator(
      onRefresh:load,
      child:CustomScrollView(
        slivers:[
          SliverToBoxAdapter(
            child:Padding(
              padding:const EdgeInsets.fromLTRB(10,10,10,4),
              child:Row(
                children:[
                  Expanded(child:SearchBox(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SearchScreen())))),
                  const SizedBox(width:4),
                  IconButton(
                    visualDensity:VisualDensity.compact,
                    onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const NotificationsScreen())),
                    icon:const Icon(Icons.mail_outline,size:22),
                  ),
                  IconButton(
                    visualDensity:VisualDensity.compact,
                    onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const WishlistScreen())),
                    icon:const Icon(Icons.favorite_border,size:22),
                  ),
                  IconButton(
                    visualDensity:VisualDensity.compact,
                    onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CartScreen())),
                    icon:const Icon(Icons.shopping_bag_outlined,size:22),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child:RootCategoryRail(
              categories:roots,
              selected:selectedRoot,
              onTap:(id)async{
                setState(()=>selectedRoot=id);
                await load();
              },
            ),
          ),
          if(loading)
            const SliverFillRemaining(hasScrollBody:false,child:Center(child:CircularProgressIndicator()))
          else ...[
            if(banners.isNotEmpty)
              SliverToBoxAdapter(
                child:PromoBannerRail(
                  banners:banners,
                  onTap:openBanner,
                ),
              ),
            if(looks.isNotEmpty)
              SliverToBoxAdapter(child:HomeLooksRail(rows:looks)),
            if(selectedRoot!=null)
              SliverToBoxAdapter(
                child:SideCategoryRail(
                  categories:side.where((e)=>int.tryParse((e['root_category_id']??'').toString())==selectedRoot).toList(),
                  onCircleTap:(circle)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SideCategoryScreen(circle:circle))),
                ),
              )
            else if(side.isNotEmpty)
              SliverToBoxAdapter(
                child:SideCategoryRail(
                  categories:side.take(3).toList(),
                  onCircleTap:(circle)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SideCategoryScreen(circle:circle))),
                ),
              ),
            const SliverToBoxAdapter(
              child:SectionTitle(title:'من أجلك'),
            ),
            SliverToBoxAdapter(
              child:ProductGrid(
                products:products,
                onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id))),
                onAdd:(p)async{
                  if(p.variantId==null){
                    Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)));
                    return;
                  }
                  try{
                    await api.addCart(p.variantId!);
                    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تمت الإضافة إلى السلة')));
                  }catch(e){
                    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
                  }
                },
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class RootCategoryRail extends StatelessWidget{
  final List<CategoryModel>categories;
  final int?selected;
  final ValueChanged<int?>onTap;
  const RootCategoryRail({super.key,required this.categories,required this.selected,required this.onTap});

  @override
  Widget build(BuildContext context)=>SizedBox(
    height:42,
    child:ListView(
      scrollDirection:Axis.horizontal,
      padding:const EdgeInsets.symmetric(horizontal:8),
      children:[
        _tab('الكل',selected==null,()=>onTap(null)),
        ...categories.map((c)=>_tab(c.name,c.id==selected,()=>onTap(c.id))),
      ],
    ),
  );

  Widget _tab(String text,bool active,VoidCallback tap)=>Padding(
    padding:const EdgeInsets.symmetric(horizontal:10),
    child:InkWell(
      onTap:tap,
      child:Center(
        child:Container(
          padding:const EdgeInsets.only(bottom:6),
          decoration:BoxDecoration(
            border:Border(bottom:BorderSide(
              color:active?Colors.black:Colors.transparent,
              width:1.6,
            )),
          ),
          child:Text(
            text,
            maxLines:1,
            overflow:TextOverflow.ellipsis,
            style:TextStyle(
              fontSize:12,
              fontWeight:active?FontWeight.w800:FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}

class PromoBannerRail extends StatefulWidget{
  final List<Map<String,dynamic>>banners;
  final ValueChanged<Map<String,dynamic>>onTap;
  const PromoBannerRail({super.key,required this.banners,required this.onTap});
  @override State<PromoBannerRail> createState()=>_PromoBannerRailState();
}
class _PromoBannerRailState extends State<PromoBannerRail>{
  int page=0;
  late final PageController controller;
  @override void initState(){super.initState();controller=PageController(viewportFraction:.965);}
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Column(
    children:[
      SizedBox(
        height:208,
        child:PageView.builder(
          controller:controller,
          itemCount:widget.banners.length,
          onPageChanged:(v)=>setState(()=>page=v),
          itemBuilder:(_,i){
            final b=widget.banners[i];
            final image=api.url((b['mobile_image_url']??b['image_url']??'').toString());
            return Padding(
              padding:const EdgeInsets.symmetric(horizontal:2),
              child:InkWell(
                onTap:()=>widget.onTap(b),
                child:ClipRRect(
                  borderRadius:BorderRadius.circular(3),
                  child:image.isEmpty
                      ?Container(color:const Color(0xFFF0F0F0))
                      :Image.network(image,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFFF0F0F0))),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height:6),
      Row(
        mainAxisAlignment:MainAxisAlignment.center,
        children:List.generate(widget.banners.length,(i)=>AnimatedContainer(
          duration:const Duration(milliseconds:150),
          margin:const EdgeInsets.symmetric(horizontal:2),
          width:i==page?16:4,
          height:2.5,
          color:i==page?Colors.black:const Color(0xFFD0D0D0),
        )),
      ),
    ],
  );
}

class SideCategoryRail extends StatelessWidget{
  final List<Map<String,dynamic>>categories;
  final ValueChanged<Map<String,dynamic>>onCircleTap;
  const SideCategoryRail({super.key,required this.categories,required this.onCircleTap});
  @override Widget build(BuildContext context){
    if(categories.isEmpty)return const SizedBox.shrink();
    final circles=categories.expand((e)=>((e['circles'] as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x))).toList();
    if(circles.isEmpty)return const SizedBox.shrink();
    return Column(
      children:[
        const SectionTitle(title:'الفئات'),
        SizedBox(
          height:108,
          child:ListView.separated(
            scrollDirection:Axis.horizontal,
            padding:const EdgeInsets.symmetric(horizontal:10),
            itemCount:circles.length,
            separatorBuilder:(_,__)=>const SizedBox(width:12),
            itemBuilder:(_,i){
              final c=circles[i];
              final image=api.url((c['image_url']??'').toString());
              return InkWell(
                onTap:()=>onCircleTap(c),
                child:SizedBox(
                  width:72,
                  child:Column(
                    children:[
                      Container(
                        width:62,
                        height:62,
                        decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFFF4F4F4)),
                        clipBehavior:Clip.antiAlias,
                        child:image.isEmpty?const Icon(Icons.category_outlined):Image.network(image,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.category_outlined)),
                      ),
                      const SizedBox(height:5),
                      Text((c['name']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class HomeTrendRail extends StatelessWidget{
  final List<Map<String,dynamic>>rows;
  const HomeTrendRail({super.key,required this.rows});
  @override Widget build(BuildContext context)=>Column(
    children:[
      const SectionTitle(title:'الترند'),
      SizedBox(
        height:188,
        child:ListView.separated(
          scrollDirection:Axis.horizontal,
          padding:const EdgeInsets.symmetric(horizontal:10),
          itemCount:rows.length,
          separatorBuilder:(_,__)=>const SizedBox(width:6),
          itemBuilder:(_,i){
            final r=rows[i];
            final bg=r['background'] is Map?Map<String,dynamic>.from(r['background']):{};
            final image=api.url((bg['url']??'').toString());
            return InkWell(
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>TrendDetailScreen(trend:r))),
              child:Container(
                width:155,
                color:Colors.white,
                child:Stack(
                  children:[
                    Positioned.fill(child:image.isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(image,fit:BoxFit.cover)),
                    Positioned(left:6,right:6,bottom:6,child:Container(
                      color:Colors.white.withOpacity(.9),
                      padding:const EdgeInsets.all(7),
                      child:Text((r['promo_text']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800)),
                    )),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class HomeLooksRail extends StatelessWidget{
  final List<Map<String,dynamic>>rows;
  const HomeLooksRail({super.key,required this.rows});
  @override Widget build(BuildContext context)=>Column(
    children:[
      SectionTitle(title:'إطلالات مختارة',onMore:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const LooksScreen()))),
      SizedBox(
        height:210,
        child:ListView.separated(
          scrollDirection:Axis.horizontal,
          padding:const EdgeInsets.symmetric(horizontal:10),
          itemCount:rows.length,
          separatorBuilder:(_,__)=>const SizedBox(width:6),
          itemBuilder:(_,i){
            final r=rows[i];
            final image=api.url((r['cover_url']??'').toString());
            return InkWell(
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LookDetailScreen(look:r))),
              child:SizedBox(
                width:150,
                child:Stack(
                  fit:StackFit.expand,
                  children:[
                    ClipRRect(
                      borderRadius:BorderRadius.circular(2),
                      child:image.isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(image,fit:BoxFit.cover),
                    ),
                    Positioned(left:0,right:0,bottom:0,child:Container(
                      padding:const EdgeInsets.symmetric(horizontal:8,vertical:7),
                      color:Colors.black.withOpacity(.5),
                      child:Text((r['name']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w800)),
                    )),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class BenefitsRow extends StatelessWidget{
  const BenefitsRow({super.key});
  @override
  Widget build(BuildContext context)=>Container(
    margin:const EdgeInsets.fromLTRB(8,8,8,2),
    child:Row(
      children:[
        Expanded(
          child:Container(
            height:64,
            margin:const EdgeInsets.only(left:2),
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
            color:const Color(0xFFFFFBF1),
            child:const Row(
              children:[
                Icon(Icons.local_shipping_outlined,size:20),
                SizedBox(width:8),
                Expanded(
                  child:Column(
                    mainAxisAlignment:MainAxisAlignment.center,
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Text('شحن سريع',style:TextStyle(fontSize:11,fontWeight:FontWeight.w900)),
                      Text('حسب العنوان',style:TextStyle(fontSize:9,color:ClientTheme.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child:Container(
            height:64,
            margin:const EdgeInsets.only(right:2),
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
            color:const Color(0xFFFFFBF1),
            child:const Row(
              children:[
                Icon(Icons.assignment_return_outlined,size:20),
                SizedBox(width:8),
                Expanded(
                  child:Column(
                    mainAxisAlignment:MainAxisAlignment.center,
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Text('إرجاع سهل',style:TextStyle(fontSize:11,fontWeight:FontWeight.w900)),
                      Text('وفق سياسة المتجر',style:TextStyle(fontSize:9,color:ClientTheme.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class BannerCarousel extends StatefulWidget{
  final List<BannerModel>banners;final ValueChanged<BannerModel>onTap;
  const BannerCarousel({super.key,required this.banners,required this.onTap});
  @override State<BannerCarousel> createState()=>_BannerCarouselState();
}
class _BannerCarouselState extends State<BannerCarousel>{
  int page=0;
  @override Widget build(BuildContext context)=>Column(children:[
    const SizedBox(height:6),
    SizedBox(height:190,child:PageView.builder(
      itemCount:widget.banners.length,
      controller:PageController(viewportFraction:.94),
      onPageChanged:(v)=>setState(()=>page=v),
      itemBuilder:(_,i){final b=widget.banners[i];final image=(b.mobileImage??b.image??'');return Padding(
        padding:const EdgeInsets.symmetric(horizontal:3),
        child:InkWell(onTap:()=>widget.onTap(b),child:ClipRRect(
          borderRadius:const BorderRadius.all(Radius.circular(2)),
          child:image.isEmpty?Container(color:Colors.black):Image.network(image,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:Colors.black)),
        )),
      );},
    )),
    const SizedBox(height:7),
    Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(widget.banners.length,(i)=>AnimatedContainer(duration:const Duration(milliseconds:120),margin:const EdgeInsets.symmetric(horizontal:2),width:i==page?18:5,height:3,color:i==page?Colors.black:const Color(0xFFCCCCCC)))),
  ]);
}

class CategoryCircles extends StatelessWidget{
  final List<CategoryModel>categories;
  const CategoryCircles({super.key,required this.categories});
  @override Widget build(BuildContext context)=>SizedBox(
    height:112,
    child:ListView.separated(
      scrollDirection:Axis.horizontal,padding:const EdgeInsets.fromLTRB(10,10,10,0),itemCount:categories.length,separatorBuilder:(_,__)=>const SizedBox(width:14),
      itemBuilder:(_,i){final c=categories[i];return InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CategoryScreen(categoryId:c.id))),child:SizedBox(width:64,child:Column(children:[
        Container(width:60,height:60,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFFF0F0F0)),child:c.iconUrl==null||c.iconUrl!.isEmpty?const Icon(Icons.category_outlined):ClipOval(child:Image.network(api.url(c.iconUrl),fit:BoxFit.cover,width:60,height:60,errorBuilder:(_,__,___)=>const Icon(Icons.category_outlined)))),
        const SizedBox(height:5),
        Text(c.name,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w600)),
      ])));},
    ),
  );
}

class TrendRow extends StatelessWidget{
  final List<Map<String,dynamic>> rows;
  const TrendRow({super.key,required this.rows});
  @override Widget build(BuildContext context)=>Column(children:[
    const SectionTitle(title:'الترند'),
    SizedBox(height:170,child:ListView.builder(
      scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:10),itemCount:rows.length,
      itemBuilder:(_,i){final bg=rows[i]['background']is Map?Map<String,dynamic>.from(rows[i]['background']):{};final image=api.url(bg['url']?.toString());return Container(width:145,margin:const EdgeInsets.only(left:8),color:Colors.white,child:Stack(children:[
        Positioned.fill(child:image.isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(image,fit:BoxFit.cover)),
        Positioned(left:7,right:7,bottom:7,child:Container(color:Colors.white.withOpacity(.9),padding:const EdgeInsets.all(7),child:Text((rows[i]['promo_text']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:11)))),
      ]));},
    )),
  ]);
}


class LooksRow extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const LooksRow({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SectionTitle(title: 'ستايل مختار لك'),
        SizedBox(
          height: 124,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> row = rows[index];
              final String image = api.url(row['cover_url']?.toString());
              return Container(
                width: 105,
                margin: const EdgeInsets.only(left: 8),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ClipOval(
                        child: image.isEmpty
                            ? Container(color: const Color(0xFFEDEDED))
                            : Image.network(
                                image,
                                fit: BoxFit.cover,
                                width: 105,
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (row['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class BannerLandingScreen extends StatefulWidget{
  final Map<String,dynamic> banner;
  const BannerLandingScreen({super.key,required this.banner});
  @override State<BannerLandingScreen> createState()=>_BannerLandingScreenState();
}
class _BannerLandingScreenState extends State<BannerLandingScreen>{
  Map<String,dynamic>? home;
  List<ProductModel> products=[];
  bool busy=true;
  int? rootId;
  Map<String,dynamic>? target;
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    try{
      home=await api.home();
      final targets=((widget.banner['targets'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
      target=targets.isEmpty?null:targets.first;
      rootId=int.tryParse((widget.banner['root_category_id']??'').toString());
      if(target?['type']=='category')rootId=int.tryParse((target?['id']??'').toString());
      if(target?['type']=='product') {
        products=[];
      } else {
        products=await api.feed(category:rootId);
      }
    }catch(_){}
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context){
    final image=api.url((widget.banner['mobile_image_url']??widget.banner['image_url']??'').toString());
    final side=((home?['side_categories'] as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).where((e){
      if(rootId==null)return true;
      return int.tryParse((e['root_category_id']??'').toString())==rootId;
    }).toList();
    final targetType=target?['type']?.toString();
    final targetId=int.tryParse((target?['id']??'').toString());
    return Directionality(
      textDirection:TextDirection.rtl,
      child:Scaffold(
        appBar:AppBar(title:Text((widget.banner['title']??'').toString())),
        body:busy?const Center(child:CircularProgressIndicator()):ListView(
          padding:const EdgeInsets.only(bottom:24),
          children:[
            if(image.isNotEmpty)Image.network(image,width:double.infinity,fit:BoxFit.cover),
            Padding(
              padding:const EdgeInsets.fromLTRB(12,14,12,4),
              child:Text((widget.banner['title']??'').toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
            ),
            if((widget.banner['description']??'').toString().isNotEmpty)
              Padding(
                padding:const EdgeInsets.symmetric(horizontal:12),
                child:Text(widget.banner['description'].toString(),style:const TextStyle(fontSize:12,color:ClientTheme.muted)),
              ),
            if(side.isNotEmpty)
              SideCategoryRail(
                categories:side,
                onCircleTap:(circle)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SideCategoryScreen(circle:circle))),
              ),
            if(targetType=='product'&&targetId!=null)
              Padding(
                padding:const EdgeInsets.all(12),
                child:FilledButton(
                  onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(targetId))),
                  style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),
                  child:const Text('عرض المنتج'),
                ),
              ),
            if(targetType=='style_tab')
              Padding(
                padding:const EdgeInsets.all(12),
                child:OutlinedButton(
                  onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const LooksScreen())),
                  child:const Text('استعرض الإطلالات'),
                ),
              ),
            if(products.isNotEmpty)const SectionTitle(title:'منتجات العرض'),
            if(products.isNotEmpty)
              ProductGrid(products:products,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))),
          ],
        ),
      ),
    );
  }
}

class SideCategoryScreen extends StatefulWidget{
  final Map<String,dynamic> circle;
  const SideCategoryScreen({super.key,required this.circle});
  @override State<SideCategoryScreen> createState()=>_SideCategoryScreenState();
}
class _SideCategoryScreenState extends State<SideCategoryScreen>{
  late Future<List<ProductModel>> future;
  @override void initState(){
    super.initState();
    future=api.feed(circleId:int.tryParse((widget.circle['id']??'').toString()));
  }
  @override Widget build(BuildContext context)=>Directionality(
    textDirection:TextDirection.rtl,
    child:Scaffold(
      appBar:AppBar(title:Text((widget.circle['name']??'').toString())),
      body:FutureBuilder<List<ProductModel>>(
        future:future,
        builder:(context,s){
          if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
          if(s.hasError)return Center(child:Text(s.error.toString()));
          final products=s.data??const<ProductModel>[];
          return ListView(
            padding:const EdgeInsets.only(top:8,bottom:24),
            children:[
              if((widget.circle['image_url']??'').toString().isNotEmpty)
                Padding(
                  padding:const EdgeInsets.symmetric(horizontal:10),
                  child:ClipRRect(
                    borderRadius:BorderRadius.circular(2),
                    child:Image.network(api.url(widget.circle['image_url'].toString()),height:170,fit:BoxFit.cover),
                  ),
                ),
              ProductGrid(products:products,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))),
            ],
          );
        },
      ),
    ),
  );
}

class TrendDetailScreen extends StatelessWidget{
  final Map<String,dynamic> trend;
  const TrendDetailScreen({super.key,required this.trend});
  @override Widget build(BuildContext context){
    final bg=trend['background'] is Map?Map<String,dynamic>.from(trend['background']):{};
    final ids=((trend['products'] as List?)??const[]).whereType<Map>().map((x){
      final p=x['product'];
      return p is Map?int.tryParse((p['id']??'').toString()):null;
    }).whereType<int>().toSet();
    return Directionality(
      textDirection:TextDirection.rtl,
      child:Scaffold(
        appBar:AppBar(title:Text((trend['hashtag'] is Map?trend['hashtag']['display_name']:'الترند')?.toString()??'الترند')),
        body:FutureBuilder<List<ProductModel>>(
          future:api.feed(),
          builder:(context,s){
            if(!s.hasData)return const Center(child:CircularProgressIndicator());
            final products=s.data!.where((p)=>ids.contains(p.id)).toList();
            return ListView(
              children:[
                if((bg['url']??'').toString().isNotEmpty)
                  Image.network(api.url(bg['url'].toString()),height:250,fit:BoxFit.cover),
                if((trend['promo_text']??'').toString().isNotEmpty)
                  Padding(padding:const EdgeInsets.all(12),child:Text(trend['promo_text'].toString(),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800))),
                ProductGrid(products:products,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LookDetailScreen extends StatelessWidget{
  final Map<String,dynamic> look;
  const LookDetailScreen({super.key,required this.look});
  @override Widget build(BuildContext context){
    final ids=((look['products'] as List?)??const[]).map((x)=>int.tryParse(x.toString())).whereType<int>().toSet();
    return Directionality(
      textDirection:TextDirection.rtl,
      child:Scaffold(
        appBar:AppBar(title:Text((look['name']??'').toString())),
        body:FutureBuilder<List<ProductModel>>(
          future:api.feed(),
          builder:(context,s){
            if(!s.hasData)return const Center(child:CircularProgressIndicator());
            final products=s.data!.where((p)=>ids.contains(p.id)).toList();
            return ListView(
              children:[
                if((look['cover_url']??'').toString().isNotEmpty)
                  Image.network(api.url(look['cover_url'].toString()),height:300,width:double.infinity,fit:BoxFit.cover),
                Padding(padding:const EdgeInsets.fromLTRB(12,12,12,4),child:Text((look['name']??'').toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900))),
                if((look['description']??'').toString().isNotEmpty)
                  Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Text(look['description'].toString(),style:const TextStyle(color:ClientTheme.muted,fontSize:11))),
                ProductGrid(products:products,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SearchScreen extends StatefulWidget{const SearchScreen({super.key});@override State<SearchScreen> createState()=>_SearchScreenState();}
class _SearchScreenState extends State<SearchScreen>{
  final q=TextEditingController();List<ProductModel>rows=[];bool busy=false;
  Future<void> search()async{if(q.text.trim().isEmpty)return;setState(()=>busy=true);try{rows=await api.feed(q:q.text);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}if(mounted)setState(()=>busy=false);}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:TextField(controller:q,autofocus:true,onSubmitted:(_)=>search(),textInputAction:TextInputAction.search,decoration:const InputDecoration(hintText:'ابحث',fillColor:Colors.transparent,border:InputBorder.none)),actions:[IconButton(onPressed:search,icon:const Icon(Icons.search))]),
    body:busy?const Center(child:CircularProgressIndicator()):rows.isEmpty?const Center(child:Text('ابدأ بكتابة اسم المنتج')):SingleChildScrollView(child:ProductGrid(products:rows,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id))))),
  ));
}

class CategoryHubScreen extends StatefulWidget{const CategoryHubScreen({super.key});@override State<CategoryHubScreen> createState()=>_CategoryHubScreenState();}
class _CategoryHubScreenState extends State<CategoryHubScreen>{
  List<CategoryModel>rows=[];
  @override void initState(){super.initState();api.roots().then((v){if(mounted)setState(()=>rows=v);});}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('التصنيفات',style:TextStyle(fontWeight:FontWeight.w900))),
    body:ListView.separated(padding:const EdgeInsets.all(10),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:6),itemBuilder:(_,i)=>Container(color:Colors.white,child:ListTile(title:Text(rows[i].name,style:const TextStyle(fontWeight:FontWeight.w800)),trailing:const Icon(Icons.chevron_left),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CategoryScreen(categoryId:rows[i].id)))))),
  ));
}

class CategoryScreen extends StatefulWidget{
  final int? categoryId;const CategoryScreen({super.key,this.categoryId});
  @override State<CategoryScreen> createState()=>_CategoryScreenState();
}
class _CategoryScreenState extends State<CategoryScreen>{
  List<CategoryModel>roots=[];List<CategoryModel>all=[];List<ProductModel>products=[];int?selected;bool busy=true;
  @override void initState(){super.initState();selected=widget.categoryId;load();}
  Future<void>load()async{
    setState(()=>busy=true);
    try{roots=await api.roots();all=await api.allCategories();products=await api.feed(category:selected);}catch(e){}
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context){
    final children=selected==null?const<CategoryModel>[]:all.where((x)=>x.parentId==selected).toList();
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:const Text('التصنيف',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SearchScreen())),icon:const Icon(Icons.search))]),
      body:busy?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:load,child:ListView(children:[
        CategoryTabs(categories:roots,selected:selected,onChanged:(v){setState(()=>selected=v);load();}),
        if(children.isNotEmpty)SizedBox(height:38,child:ListView.separated(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:10),itemCount:children.length,separatorBuilder:(_,__)=>const SizedBox(width:6),itemBuilder:(_,i)=>ActionChip(label:Text(children[i].name,style:const TextStyle(fontSize:10)),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CategoryScreen(categoryId:children[i].id)))))),
        Padding(padding:const EdgeInsets.fromLTRB(10,8,10,4),child:Row(children:[Expanded(child:Text(products.length.toString()+' منتج',style:const TextStyle(color:ClientTheme.muted,fontSize:11))),OutlinedButton.icon(onPressed:()=>showModalBottomSheet(context:context,builder:(_)=>const FilterSheet()),icon:const Icon(Icons.tune,size:16),label:const Text('تصفية',style:TextStyle(fontSize:11))),const SizedBox(width:5),OutlinedButton.icon(onPressed:(){},icon:const Icon(Icons.swap_vert,size:16),label:const Text('ترتيب',style:TextStyle(fontSize:11)))])),
        ProductGrid(products:products,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))),
      ])),
    ));
  }
}
class FilterSheet extends StatelessWidget{
  const FilterSheet({super.key});
  @override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Text('تصفية المنتجات',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
    const SizedBox(height:10),const Text('الفلاتر تقرأ من تعريفات الفئة في الإدارة، وسيتم توصيل القيم الديناميكية بالكامل في الخطوة التالية.'),
    const SizedBox(height:16),FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('تطبيق')),
  ])));
}

class DealsScreen extends StatefulWidget{
  final String? title;final int? categoryId;
  const DealsScreen({super.key,this.title,this.categoryId});
  @override State<DealsScreen> createState()=>_DealsScreenState();
}
class _DealsScreenState extends State<DealsScreen>{
  late Future<List<ProductModel>>future;
  @override void initState(){super.initState();future=api.feed(category:widget.categoryId);}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:Text(widget.title??'جديد وعروض',style:const TextStyle(fontWeight:FontWeight.w900))),
    body:FutureBuilder<List<ProductModel>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text(s.error.toString()));return SingleChildScrollView(child:ProductGrid(products:s.data??const[],onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))));}),
  ));
}


class PriceLine extends StatelessWidget {
  final String current;
  final String? old;

  const PriceLine({
    super.key,
    required this.current,
    this.old,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          current,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (old != null) ...[
          const SizedBox(width: 8),
          Text(
            '$old SAR',
            style: const TextStyle(
              fontSize: 12,
              color: ClientTheme.muted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ],
    );
  }
}

class TrustRow extends StatelessWidget {
  const TrustRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F7F7),
      padding: const EdgeInsets.all(12),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'شحن حسب العنوان',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'إرجاع وفق السياسة',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'دفع آمن',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductScreen extends StatefulWidget{
  final int id;const ProductScreen(this.id,{super.key});
  @override State<ProductScreen> createState()=>_ProductScreenState();
}
class _ProductScreenState extends State<ProductScreen>{
  Map<String,dynamic>?data;int imageIndex=0;bool adding=false;
  @override void initState(){super.initState();load();}
  Future<void>load()async{try{final r=await api.product(widget.id,currencyId:state.currencyId);final x=r['item'];if(mounted)setState(()=>data=x is Map?Map<String,dynamic>.from(x):null);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}
  Future<void>pickAndAdd()async{final d=data;if(d==null)return;setState(()=>adding=true);try{await showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.white,builder:(_)=>ProductSelectionSheet(data:d,onConfirm:(v,q,o)async{await api.addCart(v,q,o);}));}finally{if(mounted)setState(()=>adding=false);}}
  Future<void>review()async{final r=await showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.white,builder:(_)=>_ReviewComposer(productId:widget.id));if(r==true)load();}
  @override Widget build(BuildContext context){
    final d=data;if(d==null)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final p=d['product']is Map?Map<String,dynamic>.from(d['product']):<String,dynamic>{};
    final media=((d['media']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final badges=((d['badges']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final delivery=((d['delivery_badges']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final options=((d['options']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    final detail=d['product_detail_settings']is Map?Map<String,dynamic>.from(d['product_detail_settings']):<String,dynamic>{};
    final currency=p['display_currency']is Map?Map<String,dynamic>.from(p['display_currency']):<String,dynamic>{};
    final price=(p['display_price']??p['base_price_sar']??'0').toString(),old=(p['display_compare_price']??p['compare_at_price'])?.toString();
    final pn=double.tryParse(price)??0,on=double.tryParse(old??'')??0,disc=on>pn&&on>0?((1-pn/on)*100).round():0;
    final first=badgesFor(badges,'first'),above=badgesFor(badges,'above_image'),right=badgesFor(badges,'right_of_image'),belowPrice=badgesFor(badges,'below_price'),beforeName=badgesFor(badges,'before_name'),beforeRow=badgesFor(badges,'before_name_row'),afterName=badgesFor(badges,'after_name'),afterRow=badgesFor(badges,'after_name_row'),belowDesc=badgesFor(badges,'below_description'),afterDetails=badgesFor(badges,'after_details'),last=badgesFor(badges,'last');
    final summary=d['rating_summary']is Map?Map<String,dynamic>.from(d['rating_summary']):<String,dynamic>{};final avg=double.tryParse((summary['average']??0).toString())??0;final rc=int.tryParse((summary['count']??0).toString())??0;final reviews=((d['reviews_preview']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      body:CustomScrollView(slivers:[
        SliverAppBar(pinned:true,backgroundColor:Colors.white,title:const Text('التخفيض الصح',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CartScreen())),icon:const Icon(Icons.shopping_bag_outlined))]),
        if(first.isNotEmpty)SliverToBoxAdapter(child:_DetailBadgeRow(items:first)),
        if(above.isNotEmpty)SliverToBoxAdapter(child:_DetailBadgeRow(items:above)),
        SliverToBoxAdapter(child:ProductGallery(media:media,current:imageIndex,onChanged:(v)=>setState(()=>imageIndex=v),rightBadges:right)),
        SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(12,9,12,20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(crossAxisAlignment:CrossAxisAlignment.end,children:[Text(price+' '+(currency['symbol']??state.currencySymbol).toString(),style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),if(on>pn)Padding(padding:const EdgeInsets.only(right:7,bottom:2),child:Text(old!+' '+(currency['symbol']??state.currencySymbol).toString(),style:const TextStyle(fontSize:11,color:Color(0xFF858A91),decoration:TextDecoration.lineThrough))),if(disc>0)Padding(padding:const EdgeInsets.only(right:6,bottom:2),child:Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:3),decoration:BoxDecoration(color:const Color(0xFFFDE8E8),borderRadius:BorderRadius.circular(4)),child:Text('خصم '+disc.toString()+'%',style:const TextStyle(fontSize:8.5,fontWeight:FontWeight.w900))))]),
          if(belowPrice.isNotEmpty)Padding(padding:const EdgeInsets.only(top:5),child:_DetailBadgeRow(items:belowPrice)),const SizedBox(height:9),
          if(beforeRow.isNotEmpty)_DetailBadgeRow(items:beforeRow),
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[if(beforeName.isNotEmpty)Padding(padding:const EdgeInsets.only(left:5),child:_DetailBadgeInline(items:beforeName)),Expanded(child:Text(p['name']?.toString()??'',maxLines:int.tryParse((detail['name_max_lines']??4).toString())??4,overflow:TextOverflow.ellipsis,textAlign:TextAlign.right,style:TextStyle(fontSize:double.tryParse((detail['name_font_size']??20).toString())??20,fontWeight:_detailWeight(int.tryParse((detail['name_font_weight']??800).toString())??800)))),if(afterName.isNotEmpty)Padding(padding:const EdgeInsets.only(right:5),child:_DetailBadgeInline(items:afterName))]),
          if(afterRow.isNotEmpty)Padding(padding:const EdgeInsets.only(top:5),child:_DetailBadgeRow(items:afterRow)),
          if((p['short_description']??p['description']??'').toString().trim().isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text((p['short_description']??p['description']).toString(),style:const TextStyle(fontSize:10,height:1.55,color:ClientTheme.muted))),
          if(delivery.isNotEmpty)Padding(padding:const EdgeInsets.only(top:9),child:_DeliveryBadgeRows(items:delivery)),
          if(belowDesc.isNotEmpty)Padding(padding:const EdgeInsets.only(top:5),child:_DetailBadgeRow(items:belowDesc)),
          if(media.length>1)Padding(padding:const EdgeInsets.only(top:10),child:_ThumbnailRail(media:media,current:imageIndex,onTap:(v)=>setState(()=>imageIndex=v))),
          if(options.isNotEmpty)...options.map((o)=>Padding(padding:const EdgeInsets.only(top:12),child:_SelectableOptionPreview(option:o))),
          Padding(padding:const EdgeInsets.only(top:10),child:ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('تفاصيل المنتج',style:TextStyle(fontSize:13,fontWeight:FontWeight.w900)),children:[Align(alignment:Alignment.centerRight,child:Text((p['description']??'لا توجد تفاصيل إضافية.').toString(),style:const TextStyle(fontSize:9.5,height:1.65,color:ClientTheme.muted)))])),
          if(afterDetails.isNotEmpty)Padding(padding:const EdgeInsets.only(top:7),child:_DetailBadgeRow(items:afterDetails)),
          Padding(padding:const EdgeInsets.only(top:10),child:_ProductRating(avg:avg,count:rc,reviews:reviews,onReview:review)),
          if(last.isNotEmpty)Padding(padding:const EdgeInsets.only(top:7),child:_DetailBadgeRow(items:last)),
        ]))),
      ]),
      bottomNavigationBar:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(10,7,10,7),child:SizedBox(height:48,child:FilledButton(onPressed:adding?null:pickAndAdd,style:FilledButton.styleFrom(backgroundColor:Colors.black),child:adding?const CircularProgressIndicator(color:Colors.white):const Text('أضف إلى عربة التسوق',style:TextStyle(fontSize:11,fontWeight:FontWeight.w900)))))),
    ));
  }
}
List<Map<String,dynamic>> badgesFor(List<Map<String,dynamic>>rows,String pos)=>rows.where((b){final s=b['settings']is Map?Map<String,dynamic>.from(b['settings']):<String,dynamic>{};return s['visible']!=false&&(s['position']??b['position']??'before_name')==pos;}).toList();
FontWeight _detailWeight(int v){if(v>=900)return FontWeight.w900;if(v>=800)return FontWeight.w800;if(v>=700)return FontWeight.w700;if(v>=600)return FontWeight.w600;if(v>=500)return FontWeight.w500;return FontWeight.w400;}
class _DetailBadgeInline extends StatelessWidget{final List<Map<String,dynamic>>items;const _DetailBadgeInline({required this.items});@override Widget build(BuildContext context)=>Wrap(spacing:3,runSpacing:3,children:items.map((b)=>_DetailBadge(badge:b)).toList());}
class _DetailBadgeRow extends StatelessWidget{final List<Map<String,dynamic>>items;const _DetailBadgeRow({required this.items});@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:2),child:Wrap(alignment:WrapAlignment.end,spacing:5,runSpacing:4,children:items.map((b)=>_DetailBadge(badge:b)).toList()));}
class _DetailBadge extends StatelessWidget{final Map<String,dynamic>badge;const _DetailBadge({required this.badge});@override Widget build(BuildContext context){final s=badge['settings']is Map?Map<String,dynamic>.from(badge['settings']):<String,dynamic>{};final bg=_dc(s['background_color']??badge['bg_color'],'#111111'),fg=_dc(s['text_color']??badge['text_color'],'#FFFFFF');final fs=double.tryParse((s['font_size']??9).toString())??9;final op=(double.tryParse((s['background_opacity']??1).toString())??1).clamp(0,1);return Container(padding:EdgeInsets.symmetric(horizontal:double.tryParse((s['padding_horizontal']??6).toString())??6,vertical:double.tryParse((s['padding_vertical']??3).toString())??3),decoration:BoxDecoration(color:bg.withOpacity(op),borderRadius:BorderRadius.circular(double.tryParse((s['border_radius']??5).toString())??5),border:((double.tryParse((s['border_width']??0).toString())??0)>0)?Border.all(width:double.tryParse((s['border_width']??0).toString())??0,color:_dc(s['border_color'],'#FFFFFF')):null)),child:Text((s['text']??badge['custom_text']??badge['name']??badge['code']??'').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:fg,fontSize:fs,fontWeight:_detailWeight(int.tryParse((s['font_weight']??800).toString())??800),decoration:(s['text_decoration']??'none')=='line_through'?TextDecoration.lineThrough:TextDecoration.none)));}Color _dc(dynamic v,String fb){final s=(v??fb).toString();if(!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s))return const Color(0xFF111111);return Color(int.parse('FF'+s.substring(1),radix:16));}}
class _DeliveryBadgeRows extends StatelessWidget{final List<Map<String,dynamic>>items;const _DeliveryBadgeRows({required this.items});@override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:items.where((x)=>x['visible']!=false).map((x)=>Container(margin:const EdgeInsets.only(bottom:5),padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(7),border:Border.all(color:const Color(0xFFE7E7E7))),child:Row(children:[Text((x['icon']??'🚚').toString(),style:const TextStyle(fontSize:16)),const SizedBox(width:7),Expanded(child:Text((x['text']??'').toString(),style:TextStyle(fontSize:double.tryParse((x['font_size']??9).toString())??9,fontWeight:FontWeight.w800))),Text((x['section']??'').toString(),style:const TextStyle(fontSize:8,color:ClientTheme.muted))]))).toList());}
class _ThumbnailRail extends StatelessWidget{final List<Map<String,dynamic>>media;final int current;final ValueChanged<int>onTap;const _ThumbnailRail({required this.media,required this.current,required this.onTap});@override Widget build(BuildContext context)=>SizedBox(height:72,child:Directionality(textDirection:TextDirection.rtl,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:List.generate(media.length,(i)=>Padding(padding:const EdgeInsets.only(left:5),child:InkWell(onTap:()=>onTap(i),child:Container(width:58,height:70,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(border:Border.all(color:i==current?Colors.black:const Color(0xFFE1E1E1),width:i==current?2:1),borderRadius:BorderRadius.circular(5)),child:Image.network(api.url((media[i]['url']??'').toString()),fit:BoxFit.cover))))))));}
class _SelectableOptionPreview extends StatelessWidget{final Map<String,dynamic>option;const _SelectableOptionPreview({required this.option});@override Widget build(BuildContext context){final vals=((option['values']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text((option['name']??'اختيار').toString(),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),const SizedBox(height:4),Wrap(spacing:5,runSpacing:4,children:vals.map((v)=>Chip(label:Text((v['label']??'').toString(),style:const TextStyle(fontSize:8.5)))).toList())]);}}
class _ProductRating extends StatelessWidget{final double avg;final int count;final List<Map<String,dynamic>>reviews;final VoidCallback onReview;const _ProductRating({required this.avg,required this.count,required this.reviews,required this.onReview});@override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(9)),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[const Expanded(child:Text('التقييمات والمراجعات',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900))),SizedBox(height:36,child:OutlinedButton.icon(onPressed:onReview,icon:const Icon(Icons.star_outline,size:15),label:const Text('قيّم المنتج',style:TextStyle(fontSize:9))))]),const SizedBox(height:7),if(count>0)Row(children:[Text(avg.toStringAsFixed(1),style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900)),const SizedBox(width:6),...List.generate(5,(i)=>Icon(i<avg.round()?Icons.star:Icons.star_border,size:15,color:const Color(0xFFFFB400))),const SizedBox(width:5),Text(count.toString()+' تقييم',style:const TextStyle(fontSize:8,color:ClientTheme.muted))]) else const Text('لا توجد مراجعات منشورة بعد.',style:TextStyle(fontSize:9,color:ClientTheme.muted)),if(reviews.isNotEmpty)...[const Divider(height:18),...reviews.take(3).map((r)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[...List.generate(5,(i)=>Icon(i<(int.tryParse((r['rating']??0).toString())??0)?Icons.star:Icons.star_border,size:11,color:const Color(0xFFFFB400))),const Spacer(),const Text('عميل',style:TextStyle(fontSize:7,color:ClientTheme.muted))]),if((r['title']??'').toString().trim().isNotEmpty)Text(r['title'].toString(),style:const TextStyle(fontSize:9,fontWeight:FontWeight.w900)),if((r['body']??'').toString().trim().isNotEmpty)Text(r['body'].toString(),maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:8.5,height:1.45))])))]);}
}
class _ReviewComposer extends StatefulWidget{final int productId;const _ReviewComposer({required this.productId});@override State<_ReviewComposer> createState()=>_ReviewComposerState();}
class _ReviewComposerState extends State<_ReviewComposer>{int rating=5;bool busy=false;final title=TextEditingController(),body=TextEditingController();@override void dispose(){title.dispose();body.dispose();super.dispose();}Future<void>send()async{setState(()=>busy=true);try{await api.submitProductReview(widget.productId,rating:rating,title:title.text,body:body.text);if(mounted)Navigator.pop(context,true);}catch(e){if(mounted){setState(()=>busy=false);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}}@override Widget build(BuildContext context)=>SafeArea(child:Directionality(textDirection:TextDirection.rtl,child:Padding(padding:EdgeInsets.fromLTRB(12,10,12,MediaQuery.viewInsetsOf(context).bottom+14),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[Center(child:Container(width:38,height:4,decoration:BoxDecoration(color:const Color(0xFFD0D0D0),borderRadius:BorderRadius.circular(8)))),const SizedBox(height:10),const Text('أضف تقييمك',textAlign:TextAlign.center,style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(5,(i)=>IconButton(onPressed:busy?null:()=>setState(()=>rating=i+1),icon:Icon(i<rating?Icons.star:Icons.star_border,size:27,color:const Color(0xFFFFB400))))),TextField(controller:title,textDirection:TextDirection.rtl,decoration:const InputDecoration(labelText:'عنوان (اختياري)')),const SizedBox(height:6),TextField(controller:body,maxLines:4,textDirection:TextDirection.rtl,decoration:const InputDecoration(labelText:'مراجعتك')),const SizedBox(height:9),SizedBox(height:46,child:FilledButton(onPressed:busy?null:send,style:FilledButton.styleFrom(backgroundColor:Colors.black),child:busy?const CircularProgressIndicator(color:Colors.white):const Text('إرسال التقييم')))]))));
}
class ProductGallery extends StatelessWidget{final List<Map<String,dynamic>>media;final int current;final ValueChanged<int>onChanged;final List<Map<String,dynamic>>rightBadges;const ProductGallery({super.key,required this.media,required this.current,required this.onChanged,this.rightBadges=const[]});@override Widget build(BuildContext context){final count=media.isEmpty?1:media.length;return Stack(children:[AspectRatio(aspectRatio:.84,child:PageView.builder(reverse:true,itemCount:count,onPageChanged:onChanged,itemBuilder:(context,index){if(media.isEmpty)return Container(color:const Color(0xFFEDEDED),child:const Icon(Icons.image_outlined,size:42));final u=api.url((media[index]['url']??'').toString());return u.isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(u,fit:BoxFit.cover);})),if(rightBadges.isNotEmpty)Positioned(right:6,top:12,child:Column(children:rightBadges.take(5).map((b)=>Padding(padding:const EdgeInsets.only(bottom:4),child:_DetailBadge(badge:b))).toList()))]);}}
class OptionBlock extends StatelessWidget{final Map<String,dynamic>option;const OptionBlock({super.key,required this.option});@override Widget build(BuildContext context)=>_SelectableOptionPreview(option:option);}
class CartScreen extends StatefulWidget{const CartScreen({super.key});@override State<CartScreen> createState()=>_CartScreenState();}
class _CartScreenState extends State<CartScreen>{Map<String,dynamic>?cart;bool busy=true;@override void initState(){super.initState();load();}Future<void>load()async{if(!state.loggedIn){setState(()=>busy=false);return;}try{final d=await api.cart(currencyId:state.currencyId);cart=d['item']is Map?Map<String,dynamic>.from(d['item']):null;}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}if(mounted)setState(()=>busy=false);} @override Widget build(BuildContext context){if(!state.loggedIn)return const LoginRequired();if(busy)return const Scaffold(body:Center(child:CircularProgressIndicator()));final rows=((cart?['items']as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();final subtotal=pfText(cart?['subtotal'],'0');final currency=rows.isNotEmpty?pfText(rows.first['currency_code'],state.currencyCode):state.currencyCode;return Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:Text('السلة ('+rows.length.toString()+')',style:const TextStyle(fontWeight:FontWeight.w900))),body:rows.isEmpty?const Center(child:Text('سلتك فارغة')):ListView(children:[if((cart?['subtotal_sar']??'0').toString()!='0')CartShippingPromo(subtotalSar:pfText(cart?['subtotal_sar'])),Padding(padding:const EdgeInsets.all(8),child:ListView.separated(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:5),itemBuilder:(_,i)=>CartRow(item:rows[i],onPlus:()async{await api.cartQty(int.parse(rows[i]['id'].toString()),int.parse(rows[i]['qty'].toString())+1);load();},onMinus:()async{await api.cartQty(int.parse(rows[i]['id'].toString()),int.parse(rows[i]['qty'].toString())-1);load();},onRemove:()async{await api.removeCart(int.parse(rows[i]['id'].toString()));load();})))],),bottomNavigationBar:rows.isEmpty?null:SafeArea(child:Container(color:Colors.white,padding:const EdgeInsets.all(10),child:Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[const Expanded(child:Text('المجموع',style:TextStyle(fontWeight:FontWeight.w700))),Text(subtotal+' '+currency,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900))]),const SizedBox(height:7),SizedBox(width:double.infinity,height:48,child:FilledButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CheckoutScreen(onFinished:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const OrdersScreen()))))),style:FilledButton.styleFrom(backgroundColor:Colors.black),child:const Text('المتابعة للتوصيل والدفع')))]))));}}
class CartRow extends StatelessWidget{
  final Map<String,dynamic>item;final VoidCallback onPlus,onMinus,onRemove;
  const CartRow({super.key,required this.item,required this.onPlus,required this.onMinus,required this.onRemove});
  @override Widget build(BuildContext context)=>Container(color:Colors.white,padding:const EdgeInsets.all(8),child:Row(children:[
    SizedBox(width:86,height:108,child:(item['image_url']??'').toString().isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(item['image_url'].toString(),fit:BoxFit.cover)),
    const SizedBox(width:10),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text((item['product_name']??'منتج').toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
      const SizedBox(height:5),
      Text((item['variant_display']??'').toString(),style:const TextStyle(color:ClientTheme.muted,fontSize:10)),
      const SizedBox(height:6),
      Text((item['unit_price']??'0').toString()+' SAR',style:const TextStyle(fontSize:14,fontWeight:FontWeight.w900)),
      Row(children:[
        IconButton(onPressed:onRemove,icon:const Icon(Icons.delete_outline,size:18)),
        const Spacer(),
        Container(decoration:BoxDecoration(border:Border.all(color:ClientTheme.border)),child:Row(children:[
          InkWell(onTap:onPlus,child:const Padding(padding:EdgeInsets.all(8),child:Text('+'))),
          Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Text((item['qty']??1).toString())),
          InkWell(onTap:onMinus,child:const Padding(padding:EdgeInsets.all(8),child:Text('−'))),
        ])),
      ]),
    ])),
  ]));
}

class OrderSuccess extends StatelessWidget{
  final String no;const OrderSuccess({super.key,required this.no});
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:SafeArea(child:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    const Icon(Icons.check_circle,size:70,color:Colors.green),const SizedBox(height:12),
    const Text('تم استلام طلبك',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
    const SizedBox(height:7),Text('رقم الطلب: '+no,style:const TextStyle(color:ClientTheme.muted)),const SizedBox(height:20),
    FilledButton(onPressed:()=>Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const AppShell()),(_)=>false),style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),child:const Text('العودة للتسوق')),
  ])))));
}

class OrdersScreen extends StatefulWidget{
  final String initialFilter;
  const OrdersScreen({super.key,this.initialFilter='all'});@override State<OrdersScreen> createState()=>_OrdersScreenState();}
class _OrdersScreenState extends State<OrdersScreen>{List<Map<String,dynamic>>rows=[];late String filter;bool loading=true;@override void initState(){super.initState();load();}Future<void>load()async{try{rows=await api.orders();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}if(mounted)setState(()=>loading=false);}List<Map<String,dynamic>>get filtered=>rows.where((o){final s=pfText(o['status']);if(filter=='pending')return s=='created'||s=='awaiting_payment';if(filter=='payment')return s=='awaiting_payment';if(filter=='shipping')return s=='shipped';if(filter=='completed')return s=='delivered';return true;}).toList();@override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('طلباتي',style:TextStyle(fontWeight:FontWeight.w900))),body:loading?const Center(child:CircularProgressIndicator()):Column(children:[SizedBox(height:48,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:6),children:[_f('all','الكل',Icons.list_alt_outlined),_f('pending','قيد المراجعة',Icons.pending_actions_outlined),_f('payment','بانتظار الدفع',Icons.payments_outlined),_f('shipping','قيد الشحن',Icons.local_shipping_outlined),_f('completed','مكتملة',Icons.check_circle_outline)])),Expanded(child:filtered.isEmpty?const Center(child:Text('لا توجد طلبات بهذه الحالة.')):RefreshIndicator(onRefresh:load,child:ListView.separated(padding:const EdgeInsets.fromLTRB(9,5,9,12),itemCount:filtered.length,separatorBuilder:(_,__)=>const SizedBox(height:6),itemBuilder:(_,i){final o=filtered[i],s=pfText(o['status']),cur=o['currency']is Map?Map<String,dynamic>.from(o['currency']):<String,dynamic>{};return InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>OrderDetailScreen(int.parse(pfText(o['id']))))).then((_)=>load()),child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(10)),child:Row(children:[Container(width:37,height:37,decoration:BoxDecoration(color:const Color(0xFFF3F3F3),borderRadius:BorderRadius.circular(9)),child:Icon(orderStatusIcon(s),size:19)),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(pfText(o['order_no']),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),const SizedBox(height:2),Text(orderStatusText(s)+' · '+pfText(o['payment_status']),style:const TextStyle(fontSize:8,color:ClientTheme.muted))])),Text(pfText(o['total'],'0')+' '+pfText(cur['symbol'],state.currencySymbol),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900))])));}))))]));}
Widget _f(String k,String t,IconData i)=>Padding(padding:const EdgeInsets.symmetric(horizontal:3,vertical:5),child:ChoiceChip(avatar:Icon(i,size:14),label:Text(t,style:const TextStyle(fontSize:8)),selected:filter==k,onSelected:(_)=>setState(()=>filter=k)));
}
String orderStatusText(String s){switch(s){case'created':return'قيد المراجعة';case'awaiting_payment':return'بانتظار الدفع';case'paid':return'تم الدفع';case'processing':return'قيد التجهيز';case'shipped':return'قيد الشحن';case'delivered':return'مكتمل';case'returned':return'مرتجع';case'cancelled':return'ملغي';default:return s.isEmpty?'غير محدد':s;}}
IconData orderStatusIcon(String s){switch(s){case'created':return Icons.pending_actions_outlined;case'awaiting_payment':return Icons.payments_outlined;case'paid':return Icons.verified_outlined;case'processing':return Icons.inventory_2_outlined;case'shipped':return Icons.local_shipping_outlined;case'delivered':return Icons.check_circle_outline;case'returned':return Icons.assignment_return_outlined;case'cancelled':return Icons.cancel_outlined;default:return Icons.receipt_long_outlined;}}
class OrderDetailScreen extends StatefulWidget{final int id;const OrderDetailScreen(this.id,{super.key});@override State<OrderDetailScreen> createState()=>_OrderDetailScreenState();}
class _OrderDetailScreenState extends State<OrderDetailScreen>{Map<String,dynamic>?data;bool loading=true;@override void initState(){super.initState();load();}Future<void>load()async{try{final d=await api.order(widget.id),x=d['item'];if(mounted)setState(() { data=x is Map?Map<String,dynamic>.from(x):null; loading=false; });}catch(_){if(mounted)setState(()=>loading=false);}}@override Widget build(BuildContext context){if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));final d=data;if(d==null)return const Scaffold(body:Center(child:Text('تعذر تحميل الطلب.')));final s=pfText(d['status']),editable=s=='created'||s=='awaiting_payment',cur=d['currency']is Map?Map<String,dynamic>.from(d['currency']):<String,dynamic>{},addr=d['address_snapshot']is Map?Map<String,dynamic>.from(d['address_snapshot']):<String,dynamic>{};final items=((d['items']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();final pays=((d['payments']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();final proofs=((d['payment_proofs']as List?)??const[]).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();final method=d['payment_method']is Map?Map<String,dynamic>.from(d['payment_method']):<String,dynamic>{};return Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:Text(pfText(d['order_no']),style:const TextStyle(fontWeight:FontWeight.w900)),actions:[if(editable)IconButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>OrderEditScreen(order:d))).then((_){load();}),icon:const Icon(Icons.edit_outlined))]),body:ListView(padding:const EdgeInsets.all(9),children:[
  _orderSection('الحالة',orderStatusIcon(s),Row(children:[Icon(orderStatusIcon(s),size:21),const SizedBox(width:7),Text(orderStatusText(s),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),const Spacer(),Text('الدفع: '+pfText(d['payment_status']),style:const TextStyle(fontSize:8,color:ClientTheme.muted))])),
  const SizedBox(height:7),_orderSection('العنوان',Icons.location_on_outlined,Text([pfText(addr['recipient_name']),pfText(addr['country_name']),pfText(addr['region_name']),pfText(addr['city_name']),pfText(addr['city_area_name']),pfText(addr['district']),pfText(addr['street']),pfText(addr['landmark']),pfText(addr['phone'])].where((x)=>x.isNotEmpty).join('\n'),style:const TextStyle(fontSize:9.5,height:1.55))),
  const SizedBox(height:7),_orderSection('المنتجات',Icons.shopping_bag_outlined,Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:items.map((e){final vd=e['variant_display']is Map?Map<String,dynamic>.from(e['variant_display']):<String,dynamic>{},co=vd['color']is Map?Map<String,dynamic>.from(vd['color']):<String,dynamic>{},sz=vd['size']is Map?Map<String,dynamic>.from(vd['size']):<String,dynamic>{},opts=((e['options']as List?)??const[]).whereType<Map>().map((x)=>x['name'].toString()+': '+x['value'].toString()).join(' · '),media=((e['media']as List?)??const[]).whereType<Map>().toList(),img=media.isNotEmpty?api.url(pfText(media.first['url'])):'';return Container(margin:const EdgeInsets.only(bottom:6),padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:const Color(0xFFF9F9F9),borderRadius:BorderRadius.circular(8)),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[SizedBox(width:70,height:86,child:img.isEmpty?Container(color:ClientTheme.soft,child:const Icon(Icons.image_outlined)):Image.network(img,fit:BoxFit.cover)),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(pfText(e['name']),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10.5,fontWeight:FontWeight.w900)),Text('الكمية: '+pfText(e['qty'])+' · سعر الوحدة: '+pfText(e['sale_price_display'])+' '+pfText(cur['symbol'],state.currencySymbol),style:const TextStyle(fontSize:8.5)),if(co.isNotEmpty)Text('اللون: '+pfText(co['name']),style:const TextStyle(fontSize:8.5)),if(sz.isNotEmpty)Text('المقاس: '+pfText(sz['label']),style:const TextStyle(fontSize:8.5)),if(opts.isNotEmpty)Text(opts,style:const TextStyle(fontSize:8,color:ClientTheme.muted))]))]));}).toList())),
  const SizedBox(height:7),_orderSection('المبلغ',Icons.receipt_long_outlined,Column(children:[_or('المجموع',pfText(d['subtotal'],'0')+' '+pfText(cur['symbol'],state.currencySymbol)),_or('الخصم',pfText(d['discount'],'0')+' '+pfText(cur['symbol'],state.currencySymbol)),_or('التوصيل',pfText(d['shipping'],'0')+' '+pfText(cur['symbol'],state.currencySymbol)),const Divider(height:12),_or('الإجمالي',pfText(d['total'],'0')+' '+pfText(cur['symbol'],state.currencySymbol),true)])),
  const SizedBox(height:7),_orderSection('الدفع',Icons.account_balance_wallet_outlined,Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(pfText(method['name']),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),...pays.map((p)=>Text(pfText(p['status'])+' · '+pfText(p['amount'])+' '+pfText(cur['symbol'],state.currencySymbol),style:const TextStyle(fontSize:8.5))),if(editable&&pfText(d['payment_status'])!='paid')Padding(padding:const EdgeInsets.only(top:7),child:OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PaymentProofScreen(orderId:widget.id,orderNo:pfText(d['order_no']),payment:method,total:pfText(d['total'],'0'),currency:pfText(cur['symbol'],state.currencySymbol))).then((_){load();}),icon:const Icon(Icons.upload_file_outlined,size:17),label:const Text('رفع إثبات الدفع')))])),
  if(proofs.isNotEmpty)Padding(padding:const EdgeInsets.only(top:7),child:_orderSection('إثباتات الدفع',Icons.attach_file,Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:proofs.map((p)=>Text('إثبات #'+pfText(p['id'])+' · '+pfText(p['status']),style:const TextStyle(fontSize:8.5))).toList()))),
  if(pfText(d['customer_note']).isNotEmpty)Padding(padding:const EdgeInsets.only(top:7),child:_orderSection('ملاحظات الطلب',Icons.sticky_note_2_outlined,Text(pfText(d['customer_note']),style:const TextStyle(fontSize:9.5,height:1.6)))),
]));}Widget _orderSection(String t,IconData i,Widget child)=>Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(10)),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(children:[Icon(i,size:18),const SizedBox(width:6),Text(t,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900))]),const Divider(height:15),child]));Widget _or(String a,String b,[bool bold=false])=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[Expanded(child:Text(a,style:TextStyle(fontSize:9,fontWeight:bold?FontWeight.w900:FontWeight.w600))),Text(b,style:TextStyle(fontSize:bold?15:10,fontWeight:FontWeight.w900))]));}
class WishlistScreen extends StatefulWidget{const WishlistScreen({super.key});@override State<WishlistScreen> createState()=>_WishlistScreenState();}
class _WishlistScreenState extends State<WishlistScreen>{
  List<ProductModel>rows=[];bool busy=true;
  @override void initState(){super.initState();filter=widget.initialFilter;load();}
  Future<void>load()async{try{final ids=await api.wishlistIds();final all=await api.feed();rows=all.where((p)=>ids.contains(p.id)).toList();}catch(e){}if(mounted)setState(()=>busy=false);}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('المفضلة',style:TextStyle(fontWeight:FontWeight.w900))),body:busy?const Center(child:CircularProgressIndicator()):SingleChildScrollView(child:ProductGrid(products:rows,onTap:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductScreen(p.id)))))));
}


class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'حسابي',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: ListView(
          children: <Widget>[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: FutureBuilder<Map<String, dynamic>>(
                future: api.me(),
                builder: (BuildContext context,
                    AsyncSnapshot<Map<String, dynamic>> snapshot) {
                  final dynamic raw = snapshot.data?['item'];
                  final Map<String, dynamic>? customer =
                      raw is Map ? Map<String, dynamic>.from(raw) : null;
                  final String name = customer == null
                      ? 'أهلاً بك'
                      : (customer['name'] ?? 'أهلاً بك').toString();
                  final String phone = customer == null
                      ? ''
                      : (customer['phone_normalized'] ?? '').toString();

                  return Row(
                    children: <Widget>[
                      const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.person_outline),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            phone,
                            style: const TextStyle(
                              color: ClientTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            AccountTile(icon: Icons.receipt_long_outlined,title: 'طلباتي',tap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const OrdersScreen()))),
            AccountTile(icon: Icons.pending_actions_outlined,title:'طلبات قيد المراجعة',tap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const OrdersScreen(initialFilter:'pending')))),
            AccountTile(icon: Icons.payments_outlined,title:'طلبات بانتظار الدفع',tap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const OrdersScreen(initialFilter:'payment')))),
            AccountTile(
              icon: Icons.favorite_border,
              title: 'المفضلة',
              tap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WishlistScreen(),
                  ),
                );
              },
            ),
            AccountTile(
              icon: Icons.location_on_outlined,
              title: 'العناوين',
              tap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddressesScreen(),
                  ),
                );
              },
            ),
            AccountTile(
              icon: Icons.notifications_none,
              title: 'الإشعارات',
              tap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
            ),
            AccountTile(icon: Icons.policy_outlined,title:'الخصوصية والإرجاع',tap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PolicyScreen()))),
            AccountTile(
              icon: Icons.support_agent,
              title: 'خدمة العملاء',
              tap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SupportScreen(),
                  ),
                );
              },
            ),
            AccountTile(
              icon: Icons.local_fire_department_outlined,
              title: 'الترند والـLooks',
              tap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LooksScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            AccountTile(
              icon: Icons.logout,
              title: 'تسجيل الخروج',
              tap: () async {
                await api.logout();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AuthScreen(),
                  ),
                  (_) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AccountTile extends StatelessWidget{
  final IconData icon;final String title;final VoidCallback tap;
  const AccountTile({super.key,required this.icon,required this.title,required this.tap});
  @override Widget build(BuildContext context)=>ListTile(leading:Icon(icon),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),trailing:const Icon(Icons.chevron_left),onTap:tap);
}

class AddressesScreen extends StatefulWidget{const AddressesScreen({super.key});@override State<AddressesScreen> createState()=>_AddressesScreenState();}
class _AddressesScreenState extends State<AddressesScreen>{
  late Future<List<Map<String,dynamic>>>future;
  @override void initState(){super.initState();future=api.addresses();}
  Future<void>add()async{
    final name=TextEditingController(),phone=TextEditingController(),city=TextEditingController(),street=TextEditingController();
    await showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('عنوان جديد'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:name,decoration:const InputDecoration(labelText:'الاسم')),
      TextField(controller:phone,decoration:const InputDecoration(labelText:'الهاتف')),
      TextField(controller:city,decoration:const InputDecoration(labelText:'معرف المدينة')),
      TextField(controller:street,decoration:const InputDecoration(labelText:'الشارع')),
    ]),actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء')),
      FilledButton(onPressed:()async{await api.addAddress({'recipient_name':name.text,'phone':phone.text,'city_id':int.tryParse(city.text),'street':street.text,'is_default':true});if(context.mounted)Navigator.pop(context);if(mounted)setState(()=>future=api.addresses());},child:const Text('حفظ')),
    ]));
  }
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('العناوين',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:add,icon:const Icon(Icons.add))]),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());final rows=s.data??const[];return ListView.separated(padding:const EdgeInsets.all(10),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:6),itemBuilder:(_,i)=>Container(color:Colors.white,child:ListTile(title:Text((rows[i]['recipient_name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(((rows[i]['phone']??'').toString()+'\n'+(rows[i]['street']??'').toString()).trim()))));}),
  ));
}

class NotificationsScreen extends StatefulWidget{const NotificationsScreen({super.key});@override State<NotificationsScreen> createState()=>_NotificationsScreenState();}
class _NotificationsScreenState extends State<NotificationsScreen>{
  late Future<List<Map<String,dynamic>>>future;
  @override void initState(){super.initState();future=load();}
  Future<List<Map<String,dynamic>>>load()async{
    final m=await api.me();final id=int.tryParse((m['item']as Map)['id'].toString())??0;final d=await api.get('/notifications/'+id.toString());return ((d['items']as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('الإشعارات',style:TextStyle(fontWeight:FontWeight.w900))),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());final rows=s.data??const[];if(rows.isEmpty)return const Center(child:Text('لا توجد إشعارات'));return ListView.separated(itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(_,i)=>ListTile(title:Text((rows[i]['title']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((rows[i]['body']??'').toString())));}),
  ));
}

class LooksScreen extends StatefulWidget{const LooksScreen({super.key});@override State<LooksScreen> createState()=>_LooksScreenState();}
class _LooksScreenState extends State<LooksScreen>{
  late Future<Map<String,dynamic>>future;
  @override void initState(){super.initState();future=api.home();}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('الترند والـLooks',style:TextStyle(fontWeight:FontWeight.w900))),
    body:FutureBuilder<Map<String,dynamic>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());final d=s.data??{};final t=((d['trends']as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();final l=((d['looks']as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();return ListView(children:[
      const SectionTitle(title:'الترند'),
      SizedBox(height:190,child:ListView.builder(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:10),itemCount:t.length,itemBuilder:(_,i){final bg=t[i]['background']is Map?Map<String,dynamic>.from(t[i]['background']):{};final image=api.url(bg['url']?.toString());return Container(width:160,margin:const EdgeInsets.only(left:8),child:Stack(children:[Positioned.fill(child:image.isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(image,fit:BoxFit.cover)),Positioned(left:8,right:8,bottom:8,child:Container(color:Colors.white.withOpacity(.9),padding:const EdgeInsets.all(8),child:Text((t[i]['promo_text']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:11))))]));})),
      const SectionTitle(title:'Looks'),
      ...l.map((r){final image=api.url(r['cover_url']?.toString());return ListTile(leading:image.isEmpty?const CircleAvatar(child:Icon(Icons.style_outlined)):ClipOval(child:Image.network(image,width:48,height:48,fit:BoxFit.cover)),title:Text((r['name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((r['description']??'').toString()));}),
    ]);}),
  ));
}

class LoginRequired extends StatelessWidget{
  const LoginRequired({super.key});
  @override Widget build(BuildContext context)=>Center(child:FilledButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AuthScreen())),style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),child:const Text('تسجيل الدخول')));
}
