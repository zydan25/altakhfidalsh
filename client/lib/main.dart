import 'package:flutter/material.dart';
import 'api.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

final api=ApiService();
final state=ClientState();

Future<void> main()async{
  WidgetsFlutterBinding.ensureInitialized();
  await api.restore();
  runApp(const AltakhfidApp());
}

class ClientState{
  bool get loggedIn=>api.token.isNotEmpty;
  Set<int> wishlist={};
}

class AltakhfidApp extends StatelessWidget{
  const AltakhfidApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'التخفيض الصح',
    theme:ClientTheme.theme(),
    locale:const Locale('ar'),
    home:state.loggedIn?const AppShell():const AuthScreen(),
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
            if(trends.isNotEmpty)
              SliverToBoxAdapter(child:HomeTrendRail(rows:trends)),
            if(looks.isNotEmpty)
              SliverToBoxAdapter(child:HomeLooksRail(rows:looks)),
            const SliverToBoxAdapter(
              child:SectionTitle(title:'مختارات لك'),
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
  @override Widget build(BuildContext context)=>SizedBox(
    height:106,
    child:ListView.separated(
      scrollDirection:Axis.horizontal,
      padding:const EdgeInsets.fromLTRB(10,6,10,8),
      itemCount:categories.length+1,
      separatorBuilder:(_,__)=>const SizedBox(width:10),
      itemBuilder:(_,i){
        if(i==0){
          return _RootCategoryItem(
            name:'الكل',
            image:null,
            active:selected==null,
            onTap:()=>onTap(null),
          );
        }
        final c=categories[i-1];
        return _RootCategoryItem(
          name:c.name,
          image:api.url(c.iconUrl),
          active:c.id==selected,
          onTap:()=>onTap(c.id),
        );
      },
    ),
  );
}

class _RootCategoryItem extends StatelessWidget{
  final String name;
  final String?image;
  final bool active;
  final VoidCallback onTap;
  const _RootCategoryItem({required this.name,required this.image,required this.active,required this.onTap});
  @override Widget build(BuildContext context)=>InkWell(
    onTap:onTap,
    borderRadius:BorderRadius.circular(30),
    child:SizedBox(
      width:68,
      child:Column(
        children:[
          Container(
            width:62,
            height:62,
            decoration:BoxDecoration(
              color:const Color(0xFFF5F5F5),
              shape:BoxShape.circle,
              border:Border.all(color:active?Colors.black:Colors.transparent,width:1.4),
            ),
            clipBehavior:Clip.antiAlias,
            child:image==null||image!.isEmpty
                ?const Icon(Icons.grid_view_rounded,size:24)
                :Image.network(image!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.category_outlined)),
          ),
          const SizedBox(height:5),
          Text(name,maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:TextStyle(fontSize:9.5,fontWeight:active?FontWeight.w800:FontWeight.w500)),
        ],
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
        const SectionTitle(title:'تسوق حسب الفئة'),
        SizedBox(
          height:114,
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
                        width:64,
                        height:64,
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

class ProductScreen extends StatefulWidget {
  final int id;

  const ProductScreen(this.id, {super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Map<String, dynamic>? data;
  int imageIndex = 0;
  int? selectedVariant;
  bool wished = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final Map<String, dynamic> result = await api.product(widget.id);
      final dynamic value = result['item'];
      if (!mounted || value is! Map) return;

      final Map<String, dynamic> snapshot =
          Map<String, dynamic>.from(value);
      final List<Map<String, dynamic>> variants =
          ((snapshot['variants'] as List?) ?? const <dynamic>[])
              .whereType<Map>()
              .map((Map<dynamic, dynamic> row) =>
                  Map<String, dynamic>.from(row))
              .toList();

      int? firstVariant;
      if (variants.isNotEmpty) {
        firstVariant =
            int.tryParse((variants.first['id'] ?? '').toString());
      }

      setState(() {
        data = snapshot;
        selectedVariant = firstVariant;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> toggleWishlist() async {
    try {
      if (wished) {
        await api.wishlistRemove(widget.id);
      } else {
        await api.wishlistAdd(widget.id);
      }
      if (mounted) {
        setState(() => wished = !wished);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> addToCart({bool checkout = false}) async {
    if (selectedVariant == null) return;
    try {
      await api.addCart(selectedVariant!);
      if (!mounted) return;

      if (checkout) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CartScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت الإضافة إلى السلة')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final Map<String, dynamic> product = data!['product'] is Map
        ? Map<String, dynamic>.from(data!['product'])
        : <String, dynamic>{};

    final List<Map<String, dynamic>> media =
        ((data!['media'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map<dynamic, dynamic> row) =>
                Map<String, dynamic>.from(row))
            .toList();

    final List<Map<String, dynamic>> options =
        ((data!['options'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map<dynamic, dynamic> row) =>
                Map<String, dynamic>.from(row))
            .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              title: const Text(
                'التخفيض الصح',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              actions: <Widget>[
                IconButton(
                  onPressed: toggleWishlist,
                  icon: Icon(
                    wished ? Icons.favorite : Icons.favorite_border,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CartScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: ProductGallery(
                media: media,
                current: imageIndex,
                onChanged: (int value) {
                  setState(() => imageIndex = value);
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      (product['name'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PriceLine(
                      current:
                          (product['base_price_sar'] ?? '0').toString() +
                              ' SAR',
                      old: product['compare_at_price']?.toString(),
                    ),
                    const SizedBox(height: 12),
                    const TrustRow(),
                    for (final Map<String, dynamic> option in options)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OptionBlock(option: option),
                      ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'تفاصيل المنتج',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      children: <Widget>[
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            (product['description'] ?? 'لا يوجد وصف')
                                .toString(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: addToCart,
                    child: const Text('أضف إلى السلة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => addToCart(checkout: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: ClientTheme.ink,
                    ),
                    child: const Text('اشتر الآن'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProductGallery extends StatelessWidget {
  final List<Map<String, dynamic>> media;
  final int current;
  final ValueChanged<int> onChanged;

  const ProductGallery({
    super.key,
    required this.media,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final int count = media.isEmpty ? 1 : media.length;

    return Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: .84,
          child: PageView.builder(
            itemCount: count,
            onPageChanged: onChanged,
            itemBuilder: (BuildContext context, int index) {
              if (media.isEmpty) {
                return Container(
                  color: const Color(0xFFEDEDED),
                  child: const Icon(
                    Icons.image_outlined,
                    size: 42,
                  ),
                );
              }

              final String image =
                  (media[index]['url'] ?? '').toString();

              if (image.isEmpty) {
                return Container(color: const Color(0xFFEDEDED));
              }

              return Image.network(
                image,
                fit: BoxFit.cover,
              );
            },
          ),
        ),
        if (media.length > 1)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                media.length,
                (int index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: index == current ? 18 : 5,
                  height: 3,
                  color: index == current
                      ? Colors.black
                      : const Color(0xFFCCCCCC),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class OptionBlock extends StatelessWidget{
  final Map<String,dynamic>option;const OptionBlock({super.key,required this.option});
  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text((option['name']??'اختيار').toString(),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),
    const SizedBox(height:7),
    Wrap(spacing:7,runSpacing:7,children:((option['values']as List?)??const[]).whereType<Map>().map((v)=>ChoiceChip(label:Text((v['label']??'').toString(),style:const TextStyle(fontSize:10)),selected:false,onSelected:(_){},)).toList()),
  ]);
}

class CartScreen extends StatefulWidget{const CartScreen({super.key});@override State<CartScreen> createState()=>_CartScreenState();}
class _CartScreenState extends State<CartScreen>{
  Map<String,dynamic>?cart;bool busy=true;
  @override void initState(){super.initState();load();}
  Future<void>load()async{if(!state.loggedIn){setState(()=>busy=false);return;}try{final d=await api.cart();cart=d['item']is Map?Map<String,dynamic>.from(d['item']):null;}catch(e){}if(mounted)setState(()=>busy=false);}
  @override Widget build(BuildContext context){
    if(!state.loggedIn)return const LoginRequired();
    if(busy)return const Center(child:CircularProgressIndicator());
    final rows=((cart?['items']as List?)??const[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    final subtotal=(cart?['subtotal']??'0').toString();
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:Text('السلة ('+rows.length.toString()+')',style:const TextStyle(fontWeight:FontWeight.w900))),
      body:rows.isEmpty?const Center(child:Text('سلتك فارغة')):ListView.separated(padding:const EdgeInsets.all(8),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:5),itemBuilder:(_,i)=>CartRow(
        item:rows[i],
        onPlus:()async{await api.cartQty(int.parse(rows[i]['id'].toString()),int.parse(rows[i]['qty'].toString())+1);load();},
        onMinus:()async{await api.cartQty(int.parse(rows[i]['id'].toString()),int.parse(rows[i]['qty'].toString())-1);load();},
        onRemove:()async{await api.removeCart(int.parse(rows[i]['id'].toString()));load();},
      )),
      bottomNavigationBar:rows.isEmpty?null:SafeArea(child:Container(color:Colors.white,padding:const EdgeInsets.all(11),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Row(children:[const Expanded(child:Text('المجموع',style:TextStyle(fontWeight:FontWeight.w700))),Text(subtotal+' SAR',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900))]),
        const SizedBox(height:8),SizedBox(width:double.infinity,height:48,child:FilledButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CheckoutScreen())),style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),child:const Text('المتابعة للدفع'))),
      ]))),
    ));
  }
}

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

class CheckoutScreen extends StatefulWidget{const CheckoutScreen({super.key});@override State<CheckoutScreen> createState()=>_CheckoutScreenState();}
class _CheckoutScreenState extends State<CheckoutScreen>{
  List<Map<String,dynamic>>addresses=[];Map<String,dynamic>?cart;int?selected;bool busy=false;
  @override void initState(){super.initState();load();}
  Future<void>load()async{try{addresses=await api.addresses();final d=await api.cart();cart=d['item']is Map?Map<String,dynamic>.from(d['item']):null;if(addresses.isNotEmpty)selected=int.tryParse((addresses.firstWhere((e)=>e['is_default']==true,orElse:()=>addresses.first)['id']).toString());}catch(e){}if(mounted)setState((){});}
  Future<void>submit()async{
    if(selected==null||cart==null)return;
    final items=((cart!['items']as List?)??const[]).whereType<Map>().map((e)=>{'variant_id':e['variant_id'],'qty':e['qty']}).toList();
    if(items.isEmpty)return;setState(()=>busy=true);
    try{final r=await api.createOrder(selected!,items);final it=r['item'];if(!mounted)return;Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>OrderSuccess(no:it is Map?(it['order_no']??'').toString():'')),(route)=>route.isFirst);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('إتمام الطلب',style:TextStyle(fontWeight:FontWeight.w900))),
    body:ListView(padding:const EdgeInsets.all(10),children:[
      const Text('عنوان الشحن',style:TextStyle(fontSize:16,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      if(addresses.isEmpty)Container(color:Colors.white,padding:const EdgeInsets.all(14),child:const Text('أضف عنوانًا من الحساب أولًا.')),
      ...addresses.map((a)=>RadioListTile<int>(value:int.parse(a['id'].toString()),groupValue:selected,onChanged:(v)=>setState(()=>selected=v),title:Text((a['recipient_name']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((a['street']??'').toString()+'\n'+(a['phone']??'').toString()))),
      const SizedBox(height:12),
      Container(color:Colors.white,padding:const EdgeInsets.all(14),child:Row(children:[const Expanded(child:Text('الإجمالي',style:TextStyle(fontWeight:FontWeight.w800))),Text((cart?['subtotal']??'0').toString()+' SAR',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900))])),
    ]),
    bottomNavigationBar:addresses.isEmpty?null:SafeArea(child:Padding(padding:const EdgeInsets.all(10),child:SizedBox(height:50,child:FilledButton(onPressed:busy?null:submit,style:FilledButton.styleFrom(backgroundColor:ClientTheme.ink),child:busy?const CircularProgressIndicator(color:Colors.white):const Text('تأكيد الطلب'))))),
  ));
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

class OrdersScreen extends StatefulWidget{const OrdersScreen({super.key});@override State<OrdersScreen> createState()=>_OrdersScreenState();}
class _OrdersScreenState extends State<OrdersScreen>{
  late Future<List<Map<String,dynamic>>>future;
  @override void initState(){super.initState();future=api.orders();}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:const Text('طلباتي',style:TextStyle(fontWeight:FontWeight.w900))),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text(s.error.toString()));final rows=s.data??const[];if(rows.isEmpty)return const Center(child:Text('لا توجد طلبات'));return ListView.separated(padding:const EdgeInsets.all(10),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:6),itemBuilder:(_,i)=>Container(color:Colors.white,child:ListTile(
      title:Text((rows[i]['order_no']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
      subtitle:Text('الحالة: '+(rows[i]['status']??'').toString()+' • الدفع: '+(rows[i]['payment_status']??'').toString()),
      trailing:Text((rows[i]['total']??'0').toString()+' SAR',style:const TextStyle(fontWeight:FontWeight.w900)),
      onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>OrderDetailScreen(int.parse(rows[i]['id'].toString())))),
    )));}),
  ));
}

class OrderDetailScreen extends StatefulWidget{
  final int id;const OrderDetailScreen(this.id,{super.key});
  @override State<OrderDetailScreen> createState()=>_OrderDetailScreenState();
}
class _OrderDetailScreenState extends State<OrderDetailScreen>{
  Map<String,dynamic>?data;
  @override void initState(){super.initState();api.order(widget.id).then((v){if(mounted)setState(()=>data=v['item']is Map?Map<String,dynamic>.from(v['item']):null);});}
  @override Widget build(BuildContext context){
    if(data==null)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final items=((data!['items']as List?)??const[]).whereType<Map>().toList();
    final shipments=((data!['shipments']as List?)??const[]).whereType<Map>().toList();
    return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppBar(title:Text((data!['order_no']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900))),
      body:ListView(padding:const EdgeInsets.all(10),children:[
        Container(color:Colors.white,padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('الحالة الحالية: '+(data!['status']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
          const SizedBox(height:6),Text('الشحن: '+(data!['shipping_status']??'').toString()),Text('الدفع: '+(data!['payment_status']??'').toString()),
          const SizedBox(height:8),Text('الإجمالي: '+(data!['total']??'0').toString()+' SAR',style:const TextStyle(fontWeight:FontWeight.w900)),
        ])),
        ...items.map((raw){final e=Map<String,dynamic>.from(raw);final media=(e['media']as List?)??const[];final image=media.isNotEmpty?api.url((media.first as Map)['url']?.toString()):'';return Container(color:Colors.white,margin:const EdgeInsets.only(top:6),padding:const EdgeInsets.all(8),child:Row(children:[
          SizedBox(width:76,height:94,child:image.isEmpty?Container(color:const Color(0xFFEDEDED)):Image.network(image,fit:BoxFit.cover)),
          const SizedBox(width:10),Expanded(child:Text((e['name']??'').toString()+'\n'+(e['qty']??1).toString()+' × '+(e['sale_price_display']??'0').toString(),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700))),
        ]));}),
        if(shipments.isNotEmpty)...[
          const SectionTitle(title:'تتبع الشحنة'),
          ...shipments.expand((s)=>((s['events']as List?)??const[]).whereType<Map>().map((e)=>ListTile(leading:const Icon(Icons.local_shipping_outlined),title:Text((e['status']??'').toString()),subtitle:Text(((e['location']??'').toString()+' '+(e['description']??'').toString()).trim())))),
        ],
      ]),
    ));
  }
}

class WishlistScreen extends StatefulWidget{const WishlistScreen({super.key});@override State<WishlistScreen> createState()=>_WishlistScreenState();}
class _WishlistScreenState extends State<WishlistScreen>{
  List<ProductModel>rows=[];bool busy=true;
  @override void initState(){super.initState();load();}
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
            AccountTile(
              icon: Icons.shopping_bag_outlined,
              title: 'طلباتي',
              tap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OrdersScreen(),
                  ),
                );
              },
            ),
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

class SupportScreen extends StatefulWidget{const SupportScreen({super.key});@override State<SupportScreen> createState()=>_SupportScreenState();}
class _SupportScreenState extends State<SupportScreen>{
  List<Map<String,dynamic>>convs=[];int?current;List<Map<String,dynamic>>messages=[];final input=TextEditingController();
  @override void initState(){super.initState();load();}
  Future<void>load()async{convs=await api.conversations();if(mounted)setState((){});}
  Future<void>openChat(int id)async{current=id;messages=await api.messages(id);if(mounted)setState((){});}
  Future<void>send()async{final text=input.text.trim();if(current==null||text.isEmpty)return;input.clear();await api.sendMessage(current!,text);await openChat(current!);}
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:Scaffold(
    appBar:AppBar(title:Text(current==null?'خدمة العملاء':'المحادثة',style:const TextStyle(fontWeight:FontWeight.w900))),
    body:current==null?ListView.separated(padding:const EdgeInsets.all(10),itemCount:convs.length+1,separatorBuilder:(_,__)=>const SizedBox(height:6),itemBuilder:(_,i){
      if(i==0)return FilledButton.icon(onPressed:()async{final r=await api.newConversation();final id=int.tryParse((r['item']as Map)['id'].toString());if(id!=null){await load();await openChat(id);}},icon:const Icon(Icons.chat_bubble_outline),label:const Text('بدء محادثة'));
      final c=convs[i-1];return Container(color:Colors.white,child:ListTile(title:Text((c['subject']??'خدمة العملاء').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((c['status']??'').toString()),onTap:()=>openChat(int.parse(c['id'].toString()))));
    }):Column(children:[
      Expanded(child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:messages.length,itemBuilder:(_,i){final m=messages[i];final me=m['sender_type']=='customer';return Align(alignment:me?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(10),constraints:const BoxConstraints(maxWidth:300),decoration:BoxDecoration(color:me?ClientTheme.ink:const Color(0xFFF0F0F0),borderRadius:const BorderRadius.all(Radius.circular(12))),child:Text((m['body']??'').toString(),style:TextStyle(color:me?Colors.white:ClientTheme.ink,fontSize:12))));})),
      SafeArea(child:Padding(padding:const EdgeInsets.all(8),child:Row(children:[Expanded(child:TextField(controller:input,decoration:const InputDecoration(hintText:'اكتب رسالتك'))),IconButton(onPressed:send,icon:const Icon(Icons.send))]))),
    ]),
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
