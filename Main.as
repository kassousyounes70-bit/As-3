package {
    import flash.display.Sprite;
    import flash.display.Loader;
    import flash.display.LoaderInfo;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.MouseEvent;
    import flash.events.PermissionEvent;
    import flash.net.URLRequest;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.SharedObject;
    import flash.permissions.PermissionStatus;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.filesystem.File;
    import flash.filesystem.FileStream;
    import flash.filesystem.FileMode;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.utils.ByteArray;
    import flash.desktop.NativeApplication;

    [SWF(width="1280", height="720", frameRate="60", backgroundColor="#000000")]
    public class Main extends Sprite {
        private var swfLoader:Loader;
        private var urlLoader:URLLoader;
        private var uiContainer:Sprite;
        private var listContainer:Sprite;
        private var currentDir:File;
        private var errorTextField:TextField;
        private var backTextField:TextField;
        private var exitButton:Sprite;

        // الملف المؤقت الثابت
        private static const TEMP_SWF_NAME:String = "current_game.swf";
        private var tempSWFFile:File;

        // مجلد السجل في الذاكرة الداخلية — سهل الوصول
        // /storage/emulated/0/nostagames/nostagames_log.txt
        private var logFile:File;
        private var logLines:Array = [];

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

            tempSWFFile = File.applicationStorageDirectory.resolvePath(TEMP_SWF_NAME);

            // ═══════════════════════════════════════
            // طلب الصلاحيات أولاً — مرة واحدة فقط
            // عند أول تشغيل يظهر الحوار تلقائياً
            // في المرات التالية يتخطى مباشرة
            // ═══════════════════════════════════════
            if (File.permissionStatus != PermissionStatus.GRANTED) {
                var permFile:File = new File("/storage/emulated/0");
                permFile.addEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);
                permFile.requestPermission();
            } else {
                // الصلاحية موجودة مسبقاً — ابدأ مباشرة
                onPermissionGranted();
            }
        }

        private function onPermissionResult(e:PermissionEvent):void {
            (e.target as File).removeEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);

            if (e.status == PermissionStatus.GRANTED) {
                onPermissionGranted();
            } else {
                // الصلاحية مرفوضة — اعمل بمجلد التطبيق فقط
                onPermissionGranted();
            }
        }

        private function onPermissionGranted():void {
            // ═══════════════════════════════════════
            // السجل في /storage/emulated/0/nostagames/
            // مجلد سهل الوصول من أي مدير ملفات
            // ═══════════════════════════════════════
            try {
                var logDir:File = new File("/storage/emulated/0/nostagames");
                if (!logDir.exists) {
                    logDir.createDirectory();
                }
                logFile = logDir.resolvePath("nostagames_log.txt");
            } catch (e:Error) {
                // إذا فشل نستخدم مجلد التطبيق كبديل
                logFile = File.applicationStorageDirectory.resolvePath("nostagames_log.txt");
            }

            log("=== Nostagames Engine Started ===");
            log("Permission: " + File.permissionStatus);
            log("App Storage: " + File.applicationStorageDirectory.nativePath);
            log("Log File: " + logFile.nativePath);
            log("Temp SWF: " + tempSWFFile.nativePath);

            setupExitButton();
            setupFileManager();
        }

        // ═══════════════════════════════════════════
        //  نظام السجل
        // ═══════════════════════════════════════════

        private function log(msg:String):void {
            var now:Date = new Date();
            var line:String = "[" + now.toTimeString().substr(0, 8) + "] " + msg;
            logLines.push(line);
            flushLog();
        }

        private function flushLog():void {
            if (logFile == null) return;
            try {
                var stream:FileStream = new FileStream();
                stream.open(logFile, FileMode.WRITE);
                stream.writeUTFBytes(logLines.join("\n") + "\n");
                stream.close();
            } catch (e:Error) {}
        }

        // ═══════════════════════════════════════════
        //  زر الخروج ✕
        // ═══════════════════════════════════════════

        private function setupExitButton():void {
            if (exitButton && contains(exitButton)) {
                removeChild(exitButton);
            }

            exitButton = new Sprite();
            exitButton.graphics.beginFill(0xCC0000, 0.9);
            exitButton.graphics.drawRoundRect(0, 0, 80, 80, 14);
            exitButton.graphics.endFill();

            var tf:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 46, 0xFFFFFF, true);
            fmt.align = "center";
            tf.defaultTextFormat = fmt;
            tf.text = "✕";
            tf.width = 80;
            tf.height = 72;
            tf.x = 0;
            tf.y = 6;
            tf.selectable = false;
            tf.mouseEnabled = false;
            exitButton.addChild(tf);

            exitButton.x = stage.stageWidth - 90;
            exitButton.y = 10;
            exitButton.addEventListener(MouseEvent.CLICK, onExitClick);
            addChild(exitButton);
        }

        private function onExitClick(e:MouseEvent):void {
            log("=== EXIT PRESSED ===");

            // مسح كامل لمجلد App Storage
            try {
                log("--- App Storage contents ---");
                listDirRecursive(File.applicationStorageDirectory, "  ");
            } catch (err:Error) {
                log("Scan error: " + err.message);
            }

            // البحث عن #SharedObjects في كل المسارات المحتملة
            var searchPaths:Array = [
                File.applicationStorageDirectory.nativePath,
                File.applicationStorageDirectory.parent.nativePath,
                "/data/data/com.ncore.player.engine",
                "/data/user/0/com.ncore.player.engine"
            ];

            for each (var p:String in searchPaths) {
                try {
                    var dir:File = new File(p);
                    if (dir.exists) {
                        log("--- Searching: " + p + " ---");
                        listDirRecursive(dir, "  ");
                    }
                } catch (e2:Error) {
                    log("Cannot access: " + p + " — " + e2.message);
                }
            }

            log("=== END OF LOG ===");
            flushLog();

            NativeApplication.nativeApplication.exit(0);
        }

        private function listDirRecursive(dir:File, indent:String):void {
            try {
                var items:Array = dir.getDirectoryListing();
                for each (var item:File in items) {
                    if (item.isDirectory) {
                        log(indent + "[DIR] " + item.name);
                        // لا نتعمق أكثر من مستويين لتجنب الحلقات اللانهائية
                        if (indent.length < 6) {
                            listDirRecursive(item, indent + "  ");
                        }
                    } else {
                        log(indent + item.name + " (" + item.size + "b)");
                    }
                }
            } catch (e:Error) {
                log(indent + "! " + e.message);
            }
        }

        // ═══════════════════════════════════════════
        //  مدير الملفات
        // ═══════════════════════════════════════════

        private function setupFileManager():void {
            uiContainer = new Sprite();
            addChild(uiContainer);
            if (exitButton) setChildIndex(exitButton, numChildren - 1);

            listContainer = new Sprite();
            uiContainer.addChild(listContainer);

            stage.addEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onUp);

            currentDir = new File("/storage/emulated/0");
            if (!currentDir.exists) {
                currentDir = File.documentsDirectory;
            }

            log("File manager ready. Dir: " + currentDir.nativePath);
            renderDirectory(currentDir);
        }

        private function renderDirectory(dir:File):void {
            while (listContainer.numChildren > 0) listContainer.removeChildAt(0);
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
                    if (f.isDirectory) folders.push(f);
                    else if (f.extension != null && f.extension.toLowerCase() == "swf") swfs.push(f);
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
                        if (item.name != "NONE") handleItemClick(item.name);
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
        //  تشغيل اللعبة
        // ═══════════════════════════════════════════

        private function loadGame(url:String):void {
            log("Loading: " + url);

            if (uiContainer && contains(uiContainer)) removeChild(uiContainer);
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);

            cleanupErrorUI();
            cleanupLoaders();

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

            var realSize:uint = bytes.length;
            log("Bytes: " + realSize);

            try {
                var stream:FileStream = new FileStream();
                stream.open(tempSWFFile, FileMode.WRITE);
                stream.writeBytes(bytes);
                stream.close();
                log("Temp SWF OK: " + tempSWFFile.nativePath);
            } catch (err:Error) {
                log("Temp SWF FAIL: " + err.message);
            }

            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.allowCodeImport = true;

            swfLoader = new Loader();
            swfLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onGameLoaded);
            swfLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onGameError);
            swfLoader.loadBytes(bytes, context);
            addChild(swfLoader);

            try {
                var pe:ProgressEvent = new ProgressEvent(
                    ProgressEvent.PROGRESS, false, false, realSize, realSize
                );
                swfLoader.contentLoaderInfo.dispatchEvent(pe);
            } catch (de:Error) {
                log("ProgressEvent note: " + de.message);
            }

            if (exitButton) setChildIndex(exitButton, numChildren - 1);
        }

        private function onGameLoaded(e:Event):void {
            var info:LoaderInfo = e.target as LoaderInfo;

            log("Game loaded OK");
            log("  URL seen by game: " + info.url);
            log("  loaderURL: " + info.loaderURL);
            log("  frameRate: " + info.frameRate);
            log("  size: " + info.width + "x" + info.height);

            // اختبار SharedObject لمعرفة المسار الذي تستخدمه
            try {
                var so:SharedObject = SharedObject.getLocal("shopempire");
                log("  SO 'shopempire' size: " + so.size);
                log("  SO data keys: " + getSOKeys(so));
                so.close();
            } catch (soErr:Error) {
                log("  SO error: " + soErr.message);
            }

            var gameFrameRate:Number = info.frameRate;
            if (gameFrameRate > 0 && gameFrameRate <= 60) {
                stage.frameRate = gameFrameRate;
            }

            var gameW:Number = info.width > 0 ? info.width : 550;
            var gameH:Number = info.height > 0 ? info.height : 400;
            var screenW:Number = stage.stageWidth;
            var screenH:Number = stage.stageHeight;

            var scale:Number = screenH / gameH;
            if (gameW * scale > screenW) scale = screenW / gameW;

            swfLoader.scaleX = scale;
            swfLoader.scaleY = scale;
            swfLoader.x = Math.round((screenW - gameW * scale) / 2);
            swfLoader.y = Math.round((screenH - gameH * scale) / 2);

            flushLog();
        }

        private function getSOKeys(so:SharedObject):String {
            var keys:Array = [];
            for (var k:String in so.data) keys.push(k);
            return keys.length > 0 ? keys.join(", ") : "(empty)";
        }

        private function onGameError(e:IOErrorEvent):void {
            log("Game ERROR: " + e.text);
            flushLog();
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

            if (exitButton) setChildIndex(exitButton, numChildren - 1);
        }

        private function onBackToMenu(e:MouseEvent):void {
            log("Back to menu");
            cleanupLoaders();
            cleanupErrorUI();
            stage.frameRate = 60;
            while (numChildren > 0) removeChildAt(0);
            setupExitButton();
            setupFileManager();
        }

        // ═══════════════════════════════════════════
        //  دوال التنظيف
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
