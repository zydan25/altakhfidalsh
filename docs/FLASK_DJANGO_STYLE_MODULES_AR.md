# تنظيم Flask بأسلوب Django Apps

المشروع لا يستخدم Django لأن الخادم المطلوب هو Flask. بدل ذلك نستخدم مفهومًا مشابهًا لـDjango Apps عبر مجلدات Domain مستقلة تحت app/modules.

كل نطاق يملك Blueprint مستقلًا، ويمكنه لاحقًا امتلاك api.py وservices.py وrepository.py وschemas.py وpermissions.py وtests.

النطاقات الحالية: catalog، pricing، storefront، commerce، customer، support، promotions، after_sales، geo، system.

الـmodels بقيت مؤقتًا في app/models.py كمصدر schema واحد حتى لا تُنشأ علاقات FK مكررة. بعد تثبيت schema الأولى يمكن تقسيمها فيزيائيًا إلى app/modules/*/models.py مع الحفاظ على أسماء الجداول نفسها.