import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

class SxDeveloperSignature extends StatefulWidget {
  const SxDeveloperSignature({super.key});
  @override
  State<SxDeveloperSignature> createState() => _SxDeveloperSignatureState();
}

class _SxDeveloperSignatureState extends State<SxDeveloperSignature> {
  String _style = 'minimal';

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  Future<void> _loadStyle() async {
    try {
      final info = await api.storeInfo();
      final raw = (info['developer_signature_style'] ?? 'minimal')
          .toString().trim().toLowerCase();
      final style = const {'minimal', 'signature', 'royal', 'atelier'}.contains(raw)
          ? raw
          : 'minimal';
      if (mounted) setState(() => _style = style);
    } catch (_) {
      // The signature is never hidden when settings cannot be fetched.
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget signature;
    switch (_style) {
      case 'signature':
        signature = _signatureStyle();
        break;
      case 'royal':
        signature = _royalStyle();
        break;
      case 'atelier':
        signature = _atelierStyle();
        break;
      default:
        signature = _minimalStyle();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: signature,
    );
  }

  Widget _minimalStyle() => Padding(
        key: const ValueKey('signature-minimal'),
        padding: const EdgeInsets.only(top: 17, bottom: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32, height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFFE4E7EC), Color(0xFF98A2B3), Color(0xFFE4E7EC)]),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'برمجة وتصميم م. زيدان العطاب',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF475467), letterSpacing: .1),
                ),
                const SizedBox(height: 3),
                const Text(
                  'يمن كود للتقنيات الذكية  ·  774952665',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.2, fontWeight: FontWeight.w600, color: Color(0xFF98A2B3)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _signatureStyle() => Padding(
        key: const ValueKey('signature-luxe'),
        padding: const EdgeInsets.fromLTRB(12, 17, 12, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF111827), Color(0xFF293444), Color(0xFF111827)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB9934A).withOpacity(.55)),
                boxShadow: const [BoxShadow(color: Color(0x17111827), blurRadius: 16, offset: Offset(0, 5))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD9B66F).withOpacity(.75)),
                      color: Colors.white.withOpacity(.04),
                    ),
                    child: const Icon(Icons.code_rounded, color: Color(0xFFE5C47D), size: 22),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('زيدان العطاب', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                      SizedBox(height: 3),
                      Text('برمجة وتصميم التطبيقات', style: TextStyle(color: Color(0xFFC5CDD8), fontSize: 8.3, fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text('YEMEN CODE  ·  774952665', textDirection: TextDirection.ltr, style: TextStyle(color: Color(0xFFE5C47D), fontSize: 7.7, fontWeight: FontWeight.w800, letterSpacing: .4)),
                    ],
                  )),
                  const Icon(Icons.auto_awesome_rounded, size: 17, color: Color(0xFFD9B66F)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _royalStyle() => Padding(
        key: const ValueKey('signature-royal'),
        padding: const EdgeInsets.fromLTRB(12, 17, 12, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 365),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6D5AB)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.workspace_premium_outlined, size: 17, color: Color(0xFF94713A)),
                  const SizedBox(width: 7),
                  const Text('يمن كود للتقنيات الذكية', style: TextStyle(color: Color(0xFF694D1F), fontSize: 9.5, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 6),
                Container(width: 70, height: 1, color: const Color(0xFFD9BD7E)),
                const SizedBox(height: 6),
                const Text('برمجة وتصميم م. زيدان العطاب  ·  774952665', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7A6A4B), fontSize: 8.1, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );

  Widget _atelierStyle() => Padding(
        key: const ValueKey('signature-atelier'),
        padding: const EdgeInsets.fromLTRB(12, 17, 12, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF0B2330),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF267984).withOpacity(.75)),
              ),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFF174D57), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.developer_mode_rounded, color: Color(0xFFB7F3E7), size: 19),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('DESIGNED WITH CARE', textDirection: TextDirection.ltr, style: TextStyle(color: Color(0xFFB7F3E7), fontSize: 7.2, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    SizedBox(height: 4),
                    Text('زيدان العطاب · يمن كود', style: TextStyle(color: Colors.white, fontSize: 9.3, fontWeight: FontWeight.w800)),
                    SizedBox(height: 3),
                    Text('774952665', textDirection: TextDirection.ltr, style: TextStyle(color: Color(0xFF8DDDD0), fontSize: 7.7, fontWeight: FontWeight.w700)),
                  ],
                )),
                const Icon(Icons.hexagon_outlined, size: 20, color: Color(0xFF70CFC0)),
              ]),
            ),
          ),
        ),
      );
}

class SearchBox extends StatelessWidget {
  final VoidCallback onTap;
  const SearchBox({super.key,required this.onTap});
  @override Widget build(BuildContext context)=>InkWell(
    onTap:onTap,
    child:Container(
      height:42,color:const Color(0xFFF3F3F3),padding:const EdgeInsets.symmetric(horizontal:12),
      child:const Row(children:[
        Icon(Icons.search_rounded,size:22),
        SizedBox(width:9),
        Expanded(child:Text('ابحث عن المنتجات، الفئات أو العلامات',overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,color:ClientTheme.muted))),
      ]),
    ),
  );
}
class CategoryTabs extends StatelessWidget {
  final List<CategoryModel> categories;
  final int? selected;
  final ValueChanged<int?> onChanged;
  const CategoryTabs({super.key,required this.categories,required this.selected,required this.onChanged});
  @override Widget build(BuildContext context)=>SizedBox(
    height:48,
    child:ListView(
      scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:8),
      children:[
        tab('الكل',selected==null,()=>onChanged(null)),
        ...categories.map((c)=>tab(c.name,c.id==selected,()=>onChanged(c.id))),
      ],
    ),
  );
  Widget tab(String text,bool active,VoidCallback tap)=>Padding(
    padding:const EdgeInsets.symmetric(horizontal:9),
    child:InkWell(onTap:tap,child:Center(child:Container(
      padding:const EdgeInsets.only(bottom:4),
      decoration:BoxDecoration(border:Border(bottom:BorderSide(color:active?Colors.black:Colors.transparent,width:2))),
      child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,fontWeight:active?FontWeight.w800:FontWeight.w500)),
    ))),
  );
}
class ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  const ProductCard({super.key,required this.product,required this.onTap,this.onAdd});
  @override Widget build(BuildContext context){
    final old=double.tryParse(product.oldPrice??'');
    final now=double.tryParse(product.price)??0;
    final discount=old!=null&&old>now;
    return InkWell(
      onTap:onTap,
      child:Container(color:Colors.white,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Stack(children:[
          AspectRatio(aspectRatio:.79,child:(product.image??'').isEmpty?Container(color:const Color(0xFFEDEDED),child:const Icon(Icons.image_outlined)):Image.network(product.image!,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFFEDEDED),child:const Icon(Icons.image_outlined)))),
          if(discount)Positioned(left:6,top:6,child:Container(color:ClientTheme.promo,padding:const EdgeInsets.symmetric(horizontal:5,vertical:3),child:Text('-'+(((old-now)/old)*100).round().toString()+'%',style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800)))),
          if(onAdd!=null)Positioned(right:5,bottom:5,child:Material(color:Colors.white.withOpacity(.94),child:InkWell(onTap:onAdd,child:const Padding(padding:EdgeInsets.all(7),child:Icon(Icons.shopping_bag_outlined,size:18))))),
        ]),
        Padding(padding:const EdgeInsets.fromLTRB(8,7,8,9),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(product.name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,height:1.3)),
          const SizedBox(height:5),
          Row(children:[
            Text(product.price+' SAR',style:const TextStyle(fontSize:13,fontWeight:FontWeight.w800)),
            if(discount)...[const SizedBox(width:6),Text(product.oldPrice??'',style:const TextStyle(fontSize:10,decoration:TextDecoration.lineThrough,color:ClientTheme.muted))],
          ]),
        ])),
      ])),
    );
  }
}
class ProductGrid extends StatelessWidget {
  final List<ProductModel> products;
  final ValueChanged<ProductModel> onTap;
  final ValueChanged<ProductModel>? onAdd;
  const ProductGrid({super.key,required this.products,required this.onTap,this.onAdd});
  @override Widget build(BuildContext context)=>GridView.builder(
    padding:const EdgeInsets.fromLTRB(7,0,7,24),
    shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
    itemCount:products.length,
    gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:2,mainAxisSpacing:2,childAspectRatio:.60),
    itemBuilder:(_,i)=>ProductCard(product:products[i],onTap:()=>onTap(products[i]),onAdd:onAdd==null?null:()=>onAdd!(products[i])),
  );
}
class SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const SectionTitle({super.key,required this.title,this.onMore});
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.fromLTRB(12,16,12,10),
    child:Row(children:[Expanded(child:Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900))),if(onMore!=null)TextButton(onPressed:onMore,child:const Text('عرض الكل',style:TextStyle(fontSize:11)))]),
  );
}
