package {
    import flash.display.Sprite;
    import flash.display.Loader;
    import flash.display.LoaderInfo;
    import flash.display.AVM1Movie;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
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
        private var errorTextField:TextField;

        // متغيرات محرك السحب والتمرير
        private var isDragging:Boolean = false;
        private var startY:Number;
        private var listStartY:Number;
        private var moveThreshold:Number = 15;
        private var hasMoved:Boolean = false;

        // ارتفاع إجمالي للقائمة لحساب حدود التمرير
        private var totalListHeight:Number = 0;

        public function Main() {
            // انتظار جاهزية الـ stage قبل أي شيء
            if (stage) {
                init();
            } else {
                addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            }
        }

        private function onAddedToStage(e:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            init();
        }

        private function init():void {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;
            setupFileManager();
        }

        // ═══════════════════════════════════════════
        //  مدير الملفات
        // ═══════════════════════════════════════════

        private function setupFileManager():void {
            uiContainer = new Sprite();
            addChild(uiContainer);

            listContainer = new Sprite();
            uiContainer.addChild(listContainer);

            stage.addEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onUp);

            currentDir = new File("/storage/emulated/0");
            if (!currentDir.exists) {
                currentDir = File.documentsDirectory;
            }

            renderDirectory(currentDir);
        }

        private function renderDirectory(dir:File):void {
            while (listContainer.numChildren > 0) {
                listContainer.removeChildAt(0);
            }
            listContainer.y = 0;
            totalListHeight = 0;

            var yPos:Number = 0;
            var format:TextFormat = new TextFormat("_sans", 40, 0xFFFFFF, true);

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

                for each (var f:File in files) {
                    if (f.name.charAt(0) == ".") continue;
                    if (f.isDirectory) {
                        folders.push(f);
                    } else if (f.extension != null && f.extension.toLowerCase() == "swf") {
                        swfs.push(f);
                    }
                }

                folders.sortOn("name", Array.CASEINSENSITIVE);
                swfs.sortOn("name", Array.CASEINSENSITIVE);

                for each (var folder:File in folders) {
                    var fBtn:Sprite = createListItem("[DIR] " + folder.name, 0xAAAAAA, format);
                    fBtn.y = yPos;
                    fBtn.name = folder.nativePath;
                    listContainer.addChild(fBtn);
                    yPos += 80;
                }

                for each (var swf:File in swfs) {
                    var sBtn:Sprite = createListItem(swf.name, 0x00FF00, format);
                    sBtn.y = yPos;
                    sBtn.name = swf.nativePath;
                    listContainer.addChild(sBtn);
                    yPos += 80;
                }

            } catch (e:Error) {
                var errBtn:Sprite = createListItem("Error: " + e.message, 0xFF4444, format);
                errBtn.name = "NONE";
                listContainer.addChild(errBtn);
                yPos += 80;
            }

            totalListHeight = yPos;
        }

        private function createListItem(txt:String, color:uint, format:TextFormat):Sprite {
            var item:Sprite = new Sprite();

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

        // ═══════════════════════════════════════════
        //  السحب والتمرير مع حدود منطقية
        // ═══════════════════════════════════════════

        private function onDown(e:MouseEvent):void {
            isDragging = true;
            hasMoved = false;
            startY = e.stageY;
            listStartY = listContainer.y;
        }

        private function onMove(e:MouseEvent):void {
            if (!isDragging) return;
            var diff:Number = e.stageY - startY;
            if (Math.abs(diff) > moveThreshold) {
                hasMoved = true;
                var newY:Number = listStartY + diff;

                // حد أعلى: لا تسحب للأسفل أكثر من الصفر
                if (newY > 0) newY = 0;

                // حد أسفل: لا تسحب أكثر من ارتفاع القائمة
                var minY:Number = stage.stageHeight - totalListHeight;
                if (totalListHeight > stage.stageHeight && newY < minY) newY = minY;

                listContainer.y = newY;
            }
        }

        private function onUp(e:MouseEvent):void {
            isDragging = false;
            if (!hasMoved) {
                for (var i:int = 0; i < listContainer.numChildren; i++) {
                    var item:Sprite = listContainer.getChildAt(i) as Sprite;
                    if (item.hitTestPoint(e.stageX, e.stageY)) {
                        if (item.name != "NONE") {
                            handleItemClick(item.name);
                        }
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
                    loadGame(f.url);
                }
            }
        }

        // ═══════════════════════════════════════════
        //  تشغيل اللعبة — مع دعم AVM1 و AVM2
        // ═══════════════════════════════════════════

        private function loadGame(path:String):void {
            // إخفاء مدير الملفات
            if (uiContainer && contains(uiContainer)) {
                removeChild(uiContainer);
            }

            // إيقاف مستمعات مدير الملفات
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);

            // إزالة رسائل الخطأ القديمة إن وجدت
            if (errorTextField && contains(errorTextField)) {
                removeChild(errorTextField);
                errorTextField = null;
            }

            // تنظيف المُحمِّل القديم بالترتيب الصحيح
            if (swfLoader) {
                swfLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, onGameLoaded);
                swfLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, onGameError);
                swfLoader.unloadAndStop(true); // ← أولاً أوقف
                if (contains(swfLoader)) removeChild(swfLoader); // ← ثم أزل
                swfLoader = null;
            }

            swfLoader = new Loader();

            // ✅ domain معزول تماماً لتجنب تعارض الكلاسات مع أي لعبة
            var context:LoaderContext = new LoaderContext(false, new ApplicationDomain(null));
            context.allowCodeImport = true;

            swfLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onGameLoaded);
            swfLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onGameError);

            swfLoader.load(new URLRequest(path), context);
            addChild(swfLoader);
        }

        private function onGameLoaded(e:Event):void {
            var info:LoaderInfo = e.target as LoaderInfo;

            var gameW:Number = info.width;
            var gameH:Number = info.height;

            // إذا كانت الأبعاد صفر نستخدم أبعاد افتراضية شائعة للألعاب القديمة
            if (gameW <= 0) gameW = 550;
            if (gameH <= 0) gameH = 400;

            var screenW:Number = stage.stageWidth;
            var screenH:Number = stage.stageHeight;

            // ✅ حساب الـ scale بناءً على الارتفاع فقط (letterbox: أسود يمين ويسار)
            // هذا يجعل اللعبة تملأ الشاشة عمودياً وتتوسط أفقياً
            var scale:Number = screenH / gameH;

            // تأكد أن العرض لا يتجاوز الشاشة
            if (gameW * scale > screenW) {
                scale = screenW / gameW;
            }

            swfLoader.scaleX = scale;
            swfLoader.scaleY = scale;

            // توسيط أفقي — المساحة السوداء تكون يمين ويسار بالتساوي
            swfLoader.x = Math.round((screenW - gameW * scale) / 2);
            // توسيط عمودي
            swfLoader.y = Math.round((screenH - gameH * scale) / 2);

            // ✅ اكتشاف نوع اللعبة AVM1 أو AVM2 وتسجيله
            if (swfLoader.content is AVM1Movie) {
                // لعبة قديمة AS1/AS2 — تعمل تلقائياً كـ AVM1Movie
                // لا نحتاج تدخل إضافي، AIR يتعامل معها
            }
            // AS3 تعمل مباشرة بدون أي معالجة إضافية
        }

        private function onGameError(e:IOErrorEvent):void {
            // إزالة المُحمِّل الفاشل
            if (swfLoader && contains(swfLoader)) {
                removeChild(swfLoader);
            }

            // عرض رسالة خطأ واضحة على الشاشة
            var format:TextFormat = new TextFormat("_sans", 36, 0xFF4444, true);
            errorTextField = new TextField();
            errorTextField.defaultTextFormat = format;
            errorTextField.multiline = true;
            errorTextField.wordWrap = true;
            errorTextField.text = "فشل تحميل اللعبة\n" + e.text;
            errorTextField.width = stage.stageWidth - 80;
            errorTextField.height = 300;
            errorTextField.x = 40;
            errorTextField.y = (stage.stageHeight / 2) - 150;
            errorTextField.selectable = false;
            addChild(errorTextField);

            // زر العودة لمدير الملفات بعد الخطأ
            var backFormat:TextFormat = new TextFormat("_sans", 40, 0xFFFF00, true);
            var backTf:TextField = new TextField();
            backTf.defaultTextFormat = backFormat;
            backTf.text = "[ اضغط هنا للعودة ]";
            backTf.width = stage.stageWidth - 80;
            backTf.height = 70;
            backTf.x = 40;
            backTf.y = (stage.stageHeight / 2) + 100;
            backTf.selectable = false;
            backTf.mouseEnabled = true;
            backTf.addEventListener(MouseEvent.CLICK, onBackToMenu);
            addChild(backTf);
        }

        private function onBackToMenu(e:MouseEvent):void {
            // تنظيف شاشة الخطأ
            while (numChildren > 0) {
                removeChildAt(0);
            }
            if (swfLoader) {
                swfLoader.unloadAndStop(true);
                swfLoader = null;
            }
            errorTextField = null;

            // العودة لمدير الملفات
            setupFileManager();
        }
    }
}
