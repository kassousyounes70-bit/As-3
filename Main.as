package {
    import flash.display.Sprite;
    import flash.display.Loader;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.net.URLRequest;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.filesystem.File;
    import flash.text.TextField;
    import flash.text.TextFormat;

    [SWF(width="1280", height="720", frameRate="60", backgroundColor="#000000")]
    public class Main extends Sprite {
        private var swfLoader:Loader;
        private var uiContainer:Sprite;
        private var listContainer:Sprite;
        private var currentDir:File;
        
        // متغيرات محرك السحب والتمرير
        private var isDragging:Boolean = false;
        private var startY:Number;
        private var listStartY:Number;
        private var moveThreshold:Number = 15; // حساسية السحب
        private var hasMoved:Boolean = false;

        public function Main() {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            setupFileManager();
        }

        private function setupFileManager():void {
            uiContainer = new Sprite();
            addChild(uiContainer);

            listContainer = new Sprite();
            uiContainer.addChild(listContainer);

            // الاستماع لأحداث اللمس على مستوى الشاشة
            stage.addEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onUp);

            // بدء التصفح من جذر الذاكرة الداخلية للهاتف
            currentDir = new File("/storage/emulated/0");
            if (!currentDir.exists) {
                currentDir = File.documentsDirectory;
            }
            
            renderDirectory(currentDir);
        }

        private function renderDirectory(dir:File):void {
            // تنظيف القائمة القديمة
            while(listContainer.numChildren > 0) {
                listContainer.removeChildAt(0);
            }
            listContainer.y = 0; // إعادة التمرير للأعلى

            var yPos:Number = 0;
            var format:TextFormat = new TextFormat("_sans", 40, 0xFFFFFF, true);
            
            // زر العودة للمجلد السابق
            if (dir.parent != null) {
                var upBtn:Sprite = createListItem("[ .. GO UP .. ]", 0xFFFF00, format);
                upBtn.y = yPos;
                upBtn.name = "UP";
                listContainer.addChild(upBtn);
                yPos += 80;
            }

            try {
                var files:Array = dir.getDirectoryListing();
                var folders:Array = [];
                var swfs:Array = [];
                
                // فلترة الملفات والمجلدات
                for each (var f:File in files) {
                    if (f.name.charAt(0) == ".") continue; // تخطي الملفات المخفية
                    if (f.isDirectory) {
                        folders.push(f);
                    } else if (f.extension != null && f.extension.toLowerCase() == "swf") {
                        swfs.push(f);
                    }
                }
                
                // ترتيب أبجدي
                folders.sortOn("name", Array.CASEINSENSITIVE);
                swfs.sortOn("name", Array.CASEINSENSITIVE);
                
                // رسم المجلدات
                for each (var folder:File in folders) {
                    var fBtn:Sprite = createListItem("[DIR] " + folder.name, 0xAAAAAA, format);
                    fBtn.y = yPos;
                    fBtn.name = folder.nativePath;
                    listContainer.addChild(fBtn);
                    yPos += 80;
                }
                
                // رسم ملفات الألعاب
                for each (var swf:File in swfs) {
                    var sBtn:Sprite = createListItem(swf.name, 0x00FF00, format);
                    sBtn.y = yPos;
                    sBtn.name = swf.nativePath;
                    listContainer.addChild(sBtn);
                    yPos += 80;
                }
            } catch(e:Error) {
                var errBtn:Sprite = createListItem("Error reading directory (Permission?)", 0xFF0000, format);
                listContainer.addChild(errBtn);
            }
        }

        private function createListItem(txt:String, color:uint, format:TextFormat):Sprite {
            var item:Sprite = new Sprite();
            
            // خلفية الزر لتسهيل اللمس
            item.graphics.beginFill(0x222222);
            item.graphics.lineStyle(2, 0x444444);
            item.graphics.drawRect(0, 0, stage.stageWidth, 75);
            item.graphics.endFill();

            var tf:TextField = new TextField();
            tf.defaultTextFormat = format;
            tf.textColor = color;
            tf.text = txt;
            tf.width = stage.stageWidth - 40;
            tf.height = 60;
            tf.x = 20;
            tf.y = 10;
            tf.selectable = false;
            tf.mouseEnabled = false;
            item.addChild(tf);

            return item;
        }

        private function onDown(e:MouseEvent):void {
            isDragging = true;
            hasMoved = false;
            startY = e.stageY;
            listStartY = listContainer.y;
        }

        private function onMove(e:MouseEvent):void {
            if (isDragging) {
                var diff:Number = e.stageY - startY;
                // التأكد من أن المستخدم يسحب وليس يضغط
                if (Math.abs(diff) > moveThreshold) {
                    hasMoved = true;
                    listContainer.y = listStartY + diff;
                }
            }
        }

        private function onUp(e:MouseEvent):void {
            isDragging = false;
            if (!hasMoved) {
                // إذا لم يتحرك، فهذا يعني أنها نقرة (Click)
                for (var i:int = 0; i < listContainer.numChildren; i++) {
                    var item:Sprite = listContainer.getChildAt(i) as Sprite;
                    if (item.hitTestPoint(e.stageX, e.stageY)) {
                        handleItemClick(item.name);
                        break;
                    }
                }
            }
        }

        private function handleItemClick(path:String):void {
            if (path == "UP") {
                if (currentDir.parent) {
                    currentDir = currentDir.parent;
                    renderDirectory(currentDir);
                }
            } else {
                var f:File = new File(path);
                if (f.isDirectory) {
                    currentDir = f;
                    renderDirectory(currentDir);
                } else {
                    // تم اختيار ملف الفلاش!
                    loadGame(f.url);
                }
            }
        }

        private function loadGame(path:String):void {
            // إخفاء وحذف واجهة مدير الملفات
            if (uiContainer && contains(uiContainer)) {
                removeChild(uiContainer);
            }
            
            // إيقاف مستمعات اللمس الخاصة بالمدير
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);

            // تشغيل اللعبة
            if (swfLoader) {
                removeChild(swfLoader);
                swfLoader.unloadAndStop();
            }
            
            swfLoader = new Loader();
            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.allowCodeImport = true;
            swfLoader.load(new URLRequest(path), context);
            addChild(swfLoader);
        }
    }
}
