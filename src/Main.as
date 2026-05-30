package {
    import flash.desktop.Clipboard;
    import flash.desktop.ClipboardFormats;
    import flash.desktop.NativeApplication;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.InvokeEvent;
    import flash.events.MouseEvent;
    import flash.events.IOErrorEvent;
    import flash.events.ErrorEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.events.PermissionEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.net.SharedObject;
    import flash.system.ApplicationDomain;
    import flash.system.Security;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;

    public class Main extends Sprite {

        // ===== مسارات البحث =====
        private static const SEARCH_PATHS:Array = [
            "/sdcard/NostaGames/",
            "/sdcard/Android/data/com.ncore.nostagames/files/flash_games/",
            "/sdcard/Download/",
            "/sdcard/"
        ];

        // ===== متغيرات واجهة المستخدم =====
        private var statusText:TextField;
        private var gameLoader:Loader;
        private var uiContainer:Sprite;
        private var foundGames:Array = [];

        // ===== نظام السجل =====
        private var logLines:Array  = [];
        private var logFile:File;

        // ===== أبعاد الشاشة =====
        private var SW:Number;
        private var SH:Number;

        // ===== ملف SWF المعلّق =====
        private var pendingSwfPath:String = null;

        // ===== عداد محاولات تحديد الموضع =====
        private var positionRetryCount:int = 0;
        private static const MAX_POSITION_RETRIES:int = 30;

        // ============================================================
        public function Main() {
            if (stage) init();
            else addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }

        private function onAddedToStage(e:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            init();
        }

        private function init():void {
            stage.align     = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.addEventListener(Event.RESIZE, onStageResize);

            SW = stage.stageWidth  > 0 ? stage.stageWidth  : 1920;
            SH = stage.stageHeight > 0 ? stage.stageHeight : 1080;

            // رفع حد Local Shared Object إلى الحد الأقصى
            unlimitedLocalStorage();

            logFile = new File("/sdcard/NostaGames/logs/nosta_player_log.txt");
            writeLog("=== Nosta Flash Player بدأ ===");
            writeLog("Stage: " + SW + "x" + SH);

            // اصطياد أي خطأ غير متوقع من الألعاب
            loaderInfo.uncaughtErrorEvents.addEventListener(
                UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError
            );

            // خلفية
            graphics.beginFill(0x0A0A0A);
            graphics.drawRect(0, 0, 4000, 4000);
            graphics.endFill();

            uiContainer = new Sprite();
            addChild(uiContainer);
            buildUI();

            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);
            NativeApplication.nativeApplication.addEventListener(Event.EXITING,      onExiting);

            requestStoragePermission();
        }

        // ============================================================
        // LOCAL STORAGE — إصلاح مشكلة "set local storage to maximum"
        // ============================================================
        private function unlimitedLocalStorage():void {
            try {
                // منح الصلاحية الكاملة لـ SharedObject
                SharedObject.defaultObjectEncoding = flash.net.ObjectEncoding.AMF3;
                var so:SharedObject = SharedObject.getLocal("__nosta_init__");
                so.flush(10 * 1024 * 1024); // طلب 10MB مبدئياً
                writeLog("SharedObject flush OK");
            } catch (e:Error) {
                writeLog("SharedObject init error: " + e.message);
            }

            // أيضاً رفع الـ quota عبر Security
            try {
                Security.allowDomain("*");
                Security.allowInsecureDomain("*");
            } catch (e:Error) {
                writeLog("Security.allowDomain error: " + e.message);
            }
        }

        // ============================================================
        // STAGE RESIZE
        // ============================================================
        private function onStageResize(e:Event):void {
            if (stage.stageWidth  > 0) SW = stage.stageWidth;
            if (stage.stageHeight > 0) SH = stage.stageHeight;
            writeLog("onResize: " + SW + "x" + SH);
            if (gameLoader && gameLoader.content) positionGame();
        }

        // ============================================================
        // PERMISSIONS
        // ============================================================
        private function requestStoragePermission():void {
            try {
                var dummy:File = File.documentsDirectory;
                dummy.addEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);
                dummy.requestPermission();
            } catch (err:Error) {
                writeLog("Permission exception: " + err.message);
                afterPermission();
            }
        }

        private function onPermissionResult(e:PermissionEvent):void {
            writeLog("Permission: " + e.status);
            afterPermission();
        }

        private function afterPermission():void {
            try {
                var d:File = new File("/sdcard/NostaGames/logs/");
                if (!d.exists) d.createDirectory();
            } catch (e:Error) {}

            if (pendingSwfPath) {
                try {
                    var f:File = new File(pendingSwfPath);
                    if (f.exists) { launchGame(f); return; }
                } catch (e:Error) {}
            }
            searchAllPaths();
        }

        // ============================================================
        // BUILD UI
        // ============================================================
        private function buildUI():void {
            var title:TextField = new TextField();
            var tf:TextFormat = new TextFormat("_sans", 26, 0x00FF00, true);
            tf.align = TextFormatAlign.CENTER;
            title.defaultTextFormat = tf;
            title.text   = "NOSTA FLASH PLAYER";
            title.width  = SW;
            title.height = 50;
            title.x = 0; title.y = 30;
            title.mouseEnabled = false;
            uiContainer.addChild(title);

            var refreshBtn:Sprite = makeButton("🔄 بحث عن ألعاب", 0x1A4A6B, 100);
            refreshBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                clearGameButtons(); searchAllPaths();
            });
            uiContainer.addChild(refreshBtn);

            var browseBtn:Sprite = makeButton("📂 استيراد SWF يدوياً", 0x1A6B1A, 210);
            browseBtn.addEventListener(MouseEvent.CLICK, onBrowseClick);
            uiContainer.addChild(browseBtn);

            statusText = new TextField();
            var stf:TextFormat = new TextFormat("_sans", 14, 0x888888);
            statusText.defaultTextFormat = stf;
            statusText.width    = SW - 40;
            statusText.height   = SH - 360;
            statusText.x = 20; statusText.y = 320;
            statusText.multiline = true;
            statusText.wordWrap  = true;
            statusText.text = "جاري التهيئة...";
            uiContainer.addChild(statusText);
        }

        private function makeButton(label:String, color:uint, yPos:Number):Sprite {
            var w:Number = Math.min(SW - 80, 500);
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(color);
            btn.graphics.drawRoundRect(0, 0, w, 80, 14);
            btn.graphics.endFill();
            btn.graphics.lineStyle(2, 0x00FF00);
            btn.graphics.drawRoundRect(0, 0, w, 80, 14);
            btn.x = (SW - w) / 2; btn.y = yPos;
            btn.useHandCursor = true; btn.buttonMode = true;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 22, 0xFFFFFF, true);
            fmt.align = TextFormatAlign.CENTER;
            lbl.defaultTextFormat = fmt;
            lbl.text   = label;
            lbl.width  = w; lbl.height = 45; lbl.y = 18;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);
            return btn;
        }

        private function clearGameButtons():void {
            while (uiContainer.numChildren > 4)
                uiContainer.removeChildAt(4);
        }

        // ============================================================
        // SEARCH
        // ============================================================
        private function searchAllPaths():void {
            foundGames = [];
            var log:String = "البحث في المسارات:\n";
            writeLog("--- بدء البحث ---");

            for each (var path:String in SEARCH_PATHS) {
                try {
                    var folder:File = new File(path);
                    log += "\n• " + path + "\n";
                    if (!folder.exists) { log += "  → غير موجود\n"; continue; }

                    var files:Array = folder.getDirectoryListing();
                    var cnt:int = 0;
                    for each (var f:File in files) {
                        if (f.extension && f.extension.toLowerCase() == "swf") {
                            foundGames.push(f);
                            cnt++;
                            log += "  ✅ " + f.name + " (" + Math.round(f.size/1024) + "KB)\n";
                            writeLog("FOUND: " + f.nativePath);
                        }
                    }
                    if (cnt == 0) log += "  → لا يوجد SWF\n";
                } catch (err:Error) {
                    log += "  ❌ " + err.message + "\n";
                    writeLog("SEARCH ERR: " + err.message);
                }
            }

            statusText.text = log;

            if (foundGames.length == 1) {
                statusText.appendText("\nتشغيل تلقائي: " + foundGames[0].name);
                launchGame(foundGames[0]);
            } else if (foundGames.length > 1) {
                showGameList();
            } else {
                statusText.appendText(
                    "\n\nلم يتم العثور على ألعاب.\nضع ملف SWF في:\n" +
                    SEARCH_PATHS[0] + "\nأو استخدم زر الاستيراد."
                );
            }
        }

        private function showGameList():void {
            clearGameButtons();
            statusText.text = "تم العثور على " + foundGames.length + " لعبة — اختر:";
            var startY:Number = 320;
            var limit:int = Math.min(foundGames.length, 8);
            for (var i:int = 0; i < limit; i++) {
                uiContainer.addChild(makeGameBtn(foundGames[i], startY + i * 85));
            }
        }

        private function makeGameBtn(f:File, y:Number,
                isDirMode:Boolean=false, isUp:Boolean=false):Sprite {
            var w:Number = SW - 40;
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0x0D1F0D);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.graphics.endFill();
            btn.graphics.lineStyle(1, 0x00AA00);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.x = 20; btn.y = y;
            btn.useHandCursor = true; btn.buttonMode = true;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 20, 0x00FF00);
            lbl.defaultTextFormat = fmt;

            if (isUp)         lbl.text = "📁 .. (العودة)";
            else if (isDirMode) lbl.text = "📁 " + f.name;
            else {
                var mb:Number = Math.round(f.size/1024/1024*10)/10;
                lbl.text = "▶  " + f.name.replace(/\.swf$/i,"") + "  [" + mb + "MB]";
            }

            lbl.width = w-20; lbl.height = 40;
            lbl.x = 10; lbl.y = 15; lbl.mouseEnabled = false;
            btn.addChild(lbl);

            var tf:File = f, dm:Boolean = isDirMode, up:Boolean = isUp;
            btn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                if (up || dm) browseDirectory(tf);
                else          launchGame(tf);
            });
            return btn;
        }

        // ============================================================
        // INVOKE
        // ============================================================
        private function onInvoke(e:InvokeEvent):void {
            writeLog("onInvoke: args=" + e.arguments.length);
            if (e.arguments && e.arguments.length > 0) {
                var raw:String = String(e.arguments[0]);
                writeLog("onInvoke arg: " + raw);
                var path:String = raw;
                if (path.indexOf("file://") == 0)
                    path = decodeURIComponent(path.substring(7));

                try {
                    var f:File = new File(path);
                    if (f.exists) { launchGame(f); return; }
                    else writeLog("onInvoke: file not found: " + path);
                } catch (err:Error) {
                    writeLog("onInvoke ERR: " + err.message);
                }
            }
            if (uiContainer.visible) searchAllPaths();
        }

        // ============================================================
        // BROWSE
        // ============================================================
        private function onBrowseClick(e:MouseEvent):void {
            browseDirectory(new File("/sdcard/"));
        }

        private function browseDirectory(dir:File):void {
            clearGameButtons();
            statusText.text = "📁 " + dir.nativePath;
            writeLog("browse: " + dir.nativePath);
            try {
                var files:Array = dir.getDirectoryListing();
                files.sortOn("name");
                var y:Number = 320, cnt:int = 0;

                if (dir.parent) {
                    uiContainer.addChild(makeGameBtn(dir.parent, y, false, true));
                    y += 85; cnt++;
                }
                for each (var f:File in files) {
                    if (cnt >= 30) break;
                    if (f.isDirectory && f.name.indexOf(".") != 0) {
                        uiContainer.addChild(makeGameBtn(f, y, true));
                        y += 85; cnt++;
                    } else if (f.extension && f.extension.toLowerCase() == "swf") {
                        uiContainer.addChild(makeGameBtn(f, y));
                        y += 85; cnt++;
                    }
                }
            } catch (err:Error) {
                statusText.text = "❌ " + err.message;
                writeLog("browse ERR: " + err.message);
            }
        }

        // ============================================================
        // LAUNCH GAME
        // ============================================================
        private function launchGame(f:File):void {
            writeLog("=== launchGame: " + f.name + " (" + f.size + " bytes) ===");

            try {
                var stream:FileStream = new FileStream();
                stream.open(f, FileMode.READ);
                var bytes:ByteArray = new ByteArray();
                stream.readBytes(bytes);
                stream.close();

                // التحقق من توقيع SWF
                bytes.position = 0;
                var sig:String = "";
                for (var i:int = 0; i < 3; i++) sig += String.fromCharCode(bytes[i]);
                writeLog("SWF sig: " + sig);

                if (sig != "CWS" && sig != "FWS" && sig != "ZWS") {
                    writeLog("❌ ليس SWF صالح: " + sig);
                    showError("الملف ليس SWF صالح\nالتوقيع: " + sig);
                    return;
                }

                // قراءة حجم SWF الداخلي من الـ header
                bytes.position = 4;
                var swfInternalSize:uint = bytes.readUnsignedInt();
                writeLog("SWF internal size: " + swfInternalSize);

                destroyLoader();
                positionRetryCount = 0;
                uiContainer.visible = false;

                gameLoader = new Loader();

                // اصطياد أخطاء اللعبة نفسها — نستمر ولا نوقف
                gameLoader.uncaughtErrorEvents.addEventListener(
                    UncaughtErrorEvent.UNCAUGHT_ERROR, onGameUncaughtError
                );
                gameLoader.contentLoaderInfo.addEventListener(Event.INIT,            onGameInit);
                gameLoader.contentLoaderInfo.addEventListener(Event.COMPLETE,        onGameComplete);
                gameLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                gameLoader.contentLoaderInfo.addEventListener(ErrorEvent.ERROR,      onLoadError);

                // وضع الـ loader خلف الـ uiContainer
                addChildAt(gameLoader, 0);

                var ctx:LoaderContext = new LoaderContext(false, new ApplicationDomain(null));
                ctx.allowCodeImport = true;

                bytes.position = 0;
                gameLoader.loadBytes(bytes, ctx);
                writeLog("loadBytes بدأ...");

            } catch (err:Error) {
                showError("خطأ تشغيل:\n" + err.message);
                writeLog("launchGame EXCEPTION: " + err.message);
            }
        }

        // ============================================================
        // GAME EVENTS
        // ============================================================
        private function onGameInit(e:Event):void {
            var info:* = gameLoader.contentLoaderInfo;
            writeLog("onGameInit: " + info.width + "x" + info.height +
                     " | frameRate=" + info.frameRate);
            positionGame();
        }

        private function onGameComplete(e:Event):void {
            writeLog("onGameComplete ✓");
            positionGame();
        }

        // ============================================================
        // POSITION GAME — مع retry للألعاب التي تأخذ وقتاً
        // ============================================================
        private function positionGame():void {
            if (!gameLoader) return;

            var info:*      = gameLoader.contentLoaderInfo;
            var swfW:Number = info.width;
            var swfH:Number = info.height;

            // إذا كانت الأبعاد صفر، ننتظر وإعادة المحاولة
            if ((swfW <= 0 || swfH <= 0) && positionRetryCount < MAX_POSITION_RETRIES) {
                positionRetryCount++;
                writeLog("positionGame: أبعاد صفر، محاولة " + positionRetryCount);
                setTimeout(positionGame, 100);
                return;
            }

            // fallback للألعاب التي لا تُعلن عن حجمها
            if (swfW <= 0) swfW = 550;
            if (swfH <= 0) swfH = 400;

            var scrW:Number = stage.stageWidth  > 0 ? stage.stageWidth  : SW;
            var scrH:Number = stage.stageHeight > 0 ? stage.stageHeight : SH;

            var scale:Number = Math.min(scrW / swfW, scrH / swfH);

            gameLoader.scaleX = scale;
            gameLoader.scaleY = scale;
            gameLoader.x = Math.round((scrW - swfW * scale) / 2);
            gameLoader.y = Math.round((scrH - swfH * scale) / 2);

            writeLog("positionGame ✓ swf=" + swfW + "x" + swfH +
                     " scale=" + scale.toFixed(3) +
                     " pos=(" + gameLoader.x + "," + gameLoader.y + ")");

            // ضمان ترتيب الطبقات: خلفية(0) → لعبة(1) → واجهة(2)
            if (contains(gameLoader)) {
                var idx:int = getChildIndex(gameLoader);
                if (idx != 1) setChildIndex(gameLoader, 1);
            }
        }

        // ============================================================
        // خطأ من داخل اللعبة — نسجّله ونستمر
        // ============================================================
        private function onGameUncaughtError(e:UncaughtErrorEvent):void {
            var msg:String = "";
            if (e.error is Error) {
                var err:Error = e.error as Error;
                msg = "Error #" + err.errorID + ": " + err.message;
                var stack:String = err.getStackTrace();
                if (stack) msg += "\n" + stack;
            } else if (e.error is ErrorEvent) {
                msg = (e.error as ErrorEvent).text;
            } else {
                msg = String(e.error);
            }

            writeLog("⚠ GameError (ignored): " + msg);

            // لا نوقف التطبيق — اللعبة ستستمر
            e.preventDefault();

            // إذا كانت شاشة سوداء بعد 2 ثانية، نحاول إعادة تحديد الموضع
            setTimeout(function():void {
                if (gameLoader && !uiContainer.visible) positionGame();
            }, 2000);
        }

        private function onLoadError(e:*):void {
            var msg:String = (e is IOErrorEvent)
                ? (e as IOErrorEvent).text
                : String(e);
            writeLog("❌ onLoadError: " + msg);
            showError("فشل تحميل اللعبة:\n" + msg);
            destroyLoader();
        }

        private function onUncaughtError(e:UncaughtErrorEvent):void {
            var msg:String = (e.error is Error)
                ? (e.error as Error).getStackTrace()
                : String(e.error);
            writeLog("!!! AppUncaughtError: " + msg);
            e.preventDefault();
        }

        // ============================================================
        // HELPERS
        // ============================================================
        private function showError(msg:String):void {
            uiContainer.visible = true;
            statusText.text = "❌ " + msg +
                "\n\n📋 السجل الكامل في:\n/sdcard/NostaGames/logs/nosta_player_log.txt";
        }

        private function destroyLoader():void {
            if (!gameLoader) return;
            try {
                gameLoader.uncaughtErrorEvents.removeEventListener(
                    UncaughtErrorEvent.UNCAUGHT_ERROR, onGameUncaughtError);
                gameLoader.contentLoaderInfo.removeEventListener(Event.INIT,            onGameInit);
                gameLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE,        onGameComplete);
                gameLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                gameLoader.contentLoaderInfo.removeEventListener(ErrorEvent.ERROR,      onLoadError);
                if (contains(gameLoader)) removeChild(gameLoader);
                gameLoader.unloadAndStop(true);
            } catch (e:Error) {
                writeLog("destroyLoader err: " + e.message);
            }
            gameLoader = null;
        }

        // ============================================================
        // EXIT
        // ============================================================
        private function onExiting(e:Event):void {
            writeLog("=== التطبيق يُغلق ===");
            flushLogToFile();
            copyLogToClipboard();
        }

        // ============================================================
        // LOG
        // ============================================================
        private function writeLog(msg:String):void {
            var now:Date = new Date();
            var ts:String = now.getHours() + ":" +
                pad2(now.getMinutes()) + ":" +
                pad2(now.getSeconds());
            logLines.push("[" + ts + "] " + msg);
            if (logLines.length % 10 == 0) flushLogToFile();
        }

        private function flushLogToFile():void {
            try {
                var d:File = new File("/sdcard/NostaGames/logs/");
                if (!d.exists) d.createDirectory();
                var s:FileStream = new FileStream();
                s.open(logFile, FileMode.WRITE);
                s.writeUTFBytes(logLines.join("\n") + "\n");
                s.close();
            } catch (e:Error) {}
        }

        private function copyLogToClipboard():void {
            try {
                Clipboard.generalClipboard.clear();
                Clipboard.generalClipboard.setData(
                    ClipboardFormats.TEXT_FORMAT,
                    "=== Nosta Flash Player Log ===\n" + logLines.join("\n")
                );
            } catch (e:Error) {}
        }

        private function pad2(n:int):String {
            return n < 10 ? "0"+n : String(n);
        }
    }
}
