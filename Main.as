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
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.filesystem.File;
    import flash.filesystem.FileStream;
    import flash.filesystem.FileMode;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.utils.ByteArray;

    [SWF(width="1280", height="720", frameRate="60", backgroundColor="#000000")]
    public class Main extends Sprite {
        private var swfLoader:Loader;
        private var urlLoader:URLLoader;
        private var uiContainer:Sprite;
        private var listContainer:Sprite;
        private var currentDir:File;
        private var errorTextField:TextField;
        private var backTextField:TextField;

        // الملف المؤقت الثابت — اسمه لا يتغير أبداً
        // هذا هو سر حل مشكلة SharedObject
        private static const TEMP_SWF_NAME:String = "current_game.swf";
        private var tempSWFFile:File;

        // متغيرات السحب والتمرير
        private var isDragging:Boolean = false;
        private var startY:Number;
        private var listStartY:Number;
        private var moveThreshold:Number = 15;
        private var hasMoved:Boolean = false;
        private var totalListHeight:Number = 0;

        public function Main() {
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

            // تحديد مسار الملف المؤقت الثابت
            // File.applicationStorageDirectory = مجلد خاص بالتطبيق دائماً موجود
            tempSWFFile = File.applicationStorageDirectory.resolvePath(TEMP_SWF_NAME);

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
        //  السحب والتمرير
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
                if (newY > 0) newY = 0;
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
        //  تشغيل اللعبة — الحل المزدوج
        //
        //  المشكلة:
        //  ┌─────────────────────────────────────────┐
        //  │ loadBytes() ← pseudo-URL يتغير كل جلسة │
        //  │ → SharedObject يُفقد عند إغلاق التطبيق │
        //  │                                         │
        //  │ load() مباشر ← bytesTotal = 0           │
        //  │ → preloader اللعبة لا يكتمل أبداً      │
        //  └─────────────────────────────────────────┘
        //
        //  الحل المزدوج:
        //  ┌─────────────────────────────────────────┐
        //  │ 1. URLLoader يقرأ bytes اللعبة          │
        //  │    → يحل bytesTotal للـ preloader       │
        //  │                                         │
        //  │ 2. نكتب الـ bytes في ملف مؤقت ثابت     │
        //  │    الاسم: "current_game.swf" دائماً     │
        //  │    → URL ثابت لا يتغير أبداً            │
        //  │                                         │
        //  │ 3. load() من الملف المؤقت الثابت        │
        //  │    → SharedObject يُحفظ ويُسترجع ✅     │
        //  │    → preloader يعمل لأن الملف محلي ✅   │
        //  └─────────────────────────────────────────┘
        // ═══════════════════════════════════════════

        private function loadGame(url:String):void {
            if (uiContainer && contains(uiContainer)) {
                removeChild(uiContainer);
            }

            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);

            cleanupErrorUI();
            cleanupLoaders();

            // الخطوة 1: اقرأ ملف اللعبة كاملاً كـ ByteArray
            urlLoader = new URLLoader();
            urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
            urlLoader.addEventListener(Event.COMPLETE, onBytesReady);
            urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onGameError);
            urlLoader.load(new URLRequest(url));
        }

        private function onBytesReady(e:Event):void {
            urlLoader.removeEventListener(Event.COMPLETE, onBytesReady);
            urlLoader.removeEventListener(IOErrorEvent.IO_ERROR, onGameError);

            var bytes:ByteArray = urlLoader.data as ByteArray;
            urlLoader = null;

            // الخطوة 2: اكتب الـ bytes في الملف المؤقت الثابت
            // "current_game.swf" — نفس الاسم دائماً لكل لعبة
            // هذا يضمن أن الـ SharedObject يجد نفس المسار في كل جلسة
            try {
                var stream:FileStream = new FileStream();
                stream.open(tempSWFFile, FileMode.WRITE);
                stream.writeBytes(bytes);
                stream.close();
            } catch (writeError:Error) {
                // إذا فشل الكتابة نحاول loadBytes كبديل
                loadViaBytes(bytes);
                return;
            }

            // الخطوة 3: حمّل من الملف المؤقت الثابت
            // الآن اللعبة ترى URL ثابت: app-storage:/current_game.swf
            // هذا URL لا يتغير أبداً بين الجلسات
            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.allowCodeImport = true;

            swfLoader = new Loader();
            swfLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onGameLoaded);
            swfLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onGameError);
            swfLoader.load(new URLRequest(tempSWFFile.url), context);
            addChild(swfLoader);
        }

        // بديل احتياطي إذا فشل الكتابة للملف المؤقت
        private function loadViaBytes(bytes:ByteArray):void {
            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.allowCodeImport = true;

            swfLoader = new Loader();
            swfLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onGameLoaded);
            swfLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onGameError);
            swfLoader.loadBytes(bytes, context);
            addChild(swfLoader);
        }

        private function onGameLoaded(e:Event):void {
            var info:LoaderInfo = e.target as LoaderInfo;

            // ✅ ضبط سرعة اللعبة تلقائياً حسب frameRate الأصلي
            var gameFrameRate:Number = info.frameRate;
            if (gameFrameRate > 0 && gameFrameRate <= 60) {
                stage.frameRate = gameFrameRate;
            }

            var gameW:Number = info.width;
            var gameH:Number = info.height;
            if (gameW <= 0) gameW = 550;
            if (gameH <= 0) gameH = 400;

            var screenW:Number = stage.stageWidth;
            var screenH:Number = stage.stageHeight;

            // ✅ توسيط مع Letterbox — أسود يمين ويسار
            var scale:Number = screenH / gameH;
            if (gameW * scale > screenW) {
                scale = screenW / gameW;
            }

            swfLoader.scaleX = scale;
            swfLoader.scaleY = scale;
            swfLoader.x = Math.round((screenW - gameW * scale) / 2);
            swfLoader.y = Math.round((screenH - gameH * scale) / 2);
        }

        private function onGameError(e:IOErrorEvent):void {
            cleanupLoaders();
            cleanupErrorUI();
            stage.frameRate = 60;

            var format:TextFormat = new TextFormat("_sans", 34, 0xFF4444, true);
            errorTextField = new TextField();
            errorTextField.defaultTextFormat = format;
            errorTextField.multiline = true;
            errorTextField.wordWrap = true;
            errorTextField.text = "فشل تحميل اللعبة\n" + e.text;
            errorTextField.width = stage.stageWidth - 80;
            errorTextField.height = 200;
            errorTextField.x = 40;
            errorTextField.y = (stage.stageHeight / 2) - 150;
            errorTextField.selectable = false;
            addChild(errorTextField);

            var backFormat:TextFormat = new TextFormat("_sans", 40, 0xFFFF00, true);
            backTextField = new TextField();
            backTextField.defaultTextFormat = backFormat;
            backTextField.text = "[ اضغط هنا للعودة ]";
            backTextField.width = stage.stageWidth - 80;
            backTextField.height = 70;
            backTextField.x = 40;
            backTextField.y = (stage.stageHeight / 2) + 80;
            backTextField.selectable = false;
            backTextField.mouseEnabled = true;
            backTextField.addEventListener(MouseEvent.CLICK, onBackToMenu);
            addChild(backTextField);
        }

        private function onBackToMenu(e:MouseEvent):void {
            cleanupLoaders();
            cleanupErrorUI();
            stage.frameRate = 60;

            while (numChildren > 0) {
                removeChildAt(0);
            }

            setupFileManager();
        }

        // ═══════════════════════════════════════════
        //  دوال مساعدة للتنظيف
        // ═══════════════════════════════════════════

        private function cleanupLoaders():void {
            if (urlLoader) {
                urlLoader.removeEventListener(Event.COMPLETE, onBytesReady);
                urlLoader.removeEventListener(IOErrorEvent.IO_ERROR, onGameError);
                try { urlLoader.close(); } catch (e:Error) {}
                urlLoader = null;
            }

            if (swfLoader) {
                swfLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, onGameLoaded);
                swfLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, onGameError);
                swfLoader.unloadAndStop(true);
                if (contains(swfLoader)) removeChild(swfLoader);
                swfLoader = null;
            }
        }

        private function cleanupErrorUI():void {
            if (errorTextField) {
                if (contains(errorTextField)) removeChild(errorTextField);
                errorTextField = null;
            }
            if (backTextField) {
                backTextField.removeEventListener(MouseEvent.CLICK, onBackToMenu);
                if (contains(backTextField)) removeChild(backTextField);
                backTextField = null;
            }
        }
    }
}
