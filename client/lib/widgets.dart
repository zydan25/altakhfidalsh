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
  bool _enabled = true;
  String _style = 'classic';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final info = await api.storeInfo();
      final rawEnabled = info['developer_signature_enabled'];
      var enabled = _enabled;
      if (rawEnabled is bool) {
        enabled = rawEnabled;
      } else if (rawEnabled != null) {
        final value = rawEnabled.toString().trim().toLowerCase();
        if (const {'1', 'true', 'yes', 'on', 'enabled'}.contains(value)) {
          enabled = true;
        } else if (const {'0', 'false', 'no', 'off', 'disabled'}.contains(value)) {
          enabled = false;
        }
      }

      final rawStyle =
          (info['developer_signature_style'] ?? _style).toString().trim().toLowerCase();
      final style = const {'classic', 'modern', 'premium'}.contains(rawStyle)
          ? rawStyle
          : 'classic';
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _style = style;
        });
      }
    } catch (_) {
      // Preserve the existing signature appearance when the API is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final Widget signature;
    switch (_style) {
      case 'modern':
        signature = _modernSignature();
        break;
      case 'premium':
        signature = _premiumSignature();
        break;
      default:
        signature = _classicSignature();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: signature,
    );
  }

  Widget _classicSignature() => Padding(
        key: const ValueKey('signature-classic'),
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.code_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'برمجة وتصميم م. زيدان العطاب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8.7,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '774952665',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 8.4,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF5F6872),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'يمن كود للتقنيات الذكية',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.2,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7A838D),
                    letterSpacing: .1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _modernSignature() => Padding(
        key: const ValueKey('signature-modern'),
        padding: const EdgeInsets.only(top: 15, bottom: 6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 370),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFF303A4C)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14111827),
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.terminal_rounded,
                      size: 23,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'برمجة وتصميم',
                          style: TextStyle(
                            color: Color(0xFFB8C4D8),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'م. زيدان العطاب',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(
                              Icons.business_outlined,
                              size: 12,
                              color: Color(0xFF9CAAC0),
                            ),
                            const Text(
                              'يمن كود للتقنيات الذكية',
                              style: TextStyle(
                                color: Color(0xFFCDD5E1),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              '774952665',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: Color(0xFF9CAAC0),
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _premiumSignature() => Padding(
        key: const ValueKey('signature-premium'),
        padding: const EdgeInsets.only(top: 15, bottom: 6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 370),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF171717), Color(0xFF29251E), Color(0xFF101010)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB99B5B), width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1FB99B5B),
                    blurRadius: 16,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC9A96E)),
                          color: const Color(0x22C9A96E),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_outlined,
                          color: Color(0xFFE8CE91),
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تطوير وتنفيذ',
                              style: TextStyle(
                                color: Color(0xFFD9C18C),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'م. زيدان العطاب',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        '774952665',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: Color(0xFFE8CE91),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: const Color(0x66C9A96E)),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.diamond_outlined,
                        color: Color(0xFFE8CE91),
                        size: 13,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'يمن كود للتقنيات الذكية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFF0DEB4),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
