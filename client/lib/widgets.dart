import 'package:flutter/material.dart';
import 'models.dart';
import 'theme.dart';

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
