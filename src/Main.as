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
    import flash.net.URLRequest;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.utils.ByteArray;

    public class Main extends Sprite {

        // ===== مسارات البحث =====
        private static const SEARCH_PATHS:Array = [
            "/sdcard/NostaGames/",
            "/sdcard/Android/data/com.ncore.nostagames/files/flash_games/",
            File.applicationStorageDirectory.nativePath + "/flash_games/",
            "/sdcard/Download/",
            "/sdcard/"
        ];

        // ===== متغيرات واجهة المستخدم =====
        private var statusText:TextField;
        private var gameLoader:Loader;
        private var uiContainer:Sprite;
        private var foundGames:Array = [];

        // ===== نظام السجل =====
        private var logLines:Array = [];
        private var logFile:File;

        // ===== أبعاد الشاشة =====
        private var SW:Number;
        private var SH:Number;

        // ===== ملف SWF المطلوب تشغيله من invoke =====
        private var pendingSwfPath:String = null;

        // ============================================================
        public function Main() {
            // تأجيل حتى يكون stage جاهزاً بالكامل
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
            // ===== إعداد Stage =====
            stage.align     = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.addEventListener(Event.RESIZE, onStageResize);

            SW = stage.stageWidth  > 0 ? stage.stageWidth  : 1920;
            SH = stage.stageHeight > 0 ? stage.stageHeight : 1080;

            // ===== إعداد السجل =====
            logFile = new File("/sdcard/NostaGames/logs/nosta_player_log.txt");
            writeLog("=== Nosta Flash Player بدأ التشغيل ===");
            writeLog("Stage: " + SW + "x" + SH);

            // ===== اصطياد الأخطاء غير المتوقعة =====
            loaderInfo.uncaughtErrorEvents.addEventListener(
                UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError
            );

            // ===== خلفية سوداء =====
            graphics.beginFill(0x0A0A0A);
            graphics.drawRect(0, 0, 4000, 4000);
            graphics.endFill();

            // ===== بناء الواجهة =====
            uiContainer = new Sprite();
            addChild(uiContainer);
            buildUI();

            // ===== الاستماع للـ Invoke وزر الخروج =====
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);
            NativeApplication.nativeApplication.addEventListener(Event.EXITING, onExiting);

            // ===== طلب صلاحيات التخزين =====
            requestStoragePermission();
        }

        // ============================================================
        // STAGE RESIZE
        // ============================================================
        private function onStageResize(e:Event):void {
            if (stage.stageWidth > 0)  SW = stage.stageWidth;
            if (stage.stageHeight > 0) SH = stage.stageHeight;
            writeLog("onResize: " + SW + "x" + SH);
            // إعادة تحديد موضع اللعبة إن كانت مشغّلة
            if (gameLoader && gameLoader.content) {
                positionGame();
            }
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
            writeLog("Permission status: " + e.status);
            afterPermission();
        }

        private function afterPermission():void {
            // إنشاء مجلد السجلات إن لم يكن موجوداً
            try {
                var logsDir:File = new File("/sdcard/NostaGames/logs/");
                if (!logsDir.exists) logsDir.createDirectory();
            } catch (err:Error) {}

            if (pendingSwfPath) {
                var f:File = new File(pendingSwfPath);
                if (f.exists) {
                    launchGame(f);
                    return;
                }
            }
            searchAllPaths();
        }

        // ============================================================
        // BUILD UI
        // ============================================================
        private function buildUI():void {
            // عنوان
            var title:TextField = new TextField();
            var tf:TextFormat = new TextFormat("_sans", 26, 0x00FF00, true);
            tf.align = TextFormatAlign.CENTER;
            title.defaultTextFormat = tf;
            title.text = "NOSTA FLASH PLAYER";
            title.width = SW;
            title.height = 50;
            title.x = 0;
            title.y = 30;
            title.mouseEnabled = false;
            uiContainer.addChild(title);

            // زر بحث
            var refreshBtn:Sprite = makeButton("🔄 بحث عن ألعاب", 0x1A4A6B, 100);
            refreshBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                clearGameButtons();
                searchAllPaths();
            });
            uiContainer.addChild(refreshBtn);

            // زر استيراد يدوي
            var browseBtn:Sprite = makeButton("📂 استيراد SWF يدوياً", 0x1A6B1A, 210);
            browseBtn.addEventListener(MouseEvent.CLICK, onBrowseClick);
            uiContainer.addChild(browseBtn);

            // نص الحالة
            statusText = new TextField();
            var stf:TextFormat = new TextFormat("_sans", 14, 0x888888);
            statusText.defaultTextFormat = stf;
            statusText.width  = SW - 40;
            statusText.height = SH - 360;
            statusText.x = 20;
            statusText.y = 320;
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
            btn.x = (SW - w) / 2;
            btn.y = yPos;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 22, 0xFFFFFF, true);
            fmt.align = TextFormatAlign.CENTER;
            lbl.defaultTextFormat = fmt;
            lbl.text   = label;
            lbl.width  = w;
            lbl.height = 45;
            lbl.y = 18;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);
            return btn;
        }

        // يحذف فقط أزرار الألعاب الديناميكية (بعد أول 4 عناصر ثابتة)
        private function clearGameButtons():void {
            while (uiContainer.numChildren > 4) {
                uiContainer.removeChildAt(4);
            }
        }

        // ============================================================
        // SEARCH
        // ============================================================
        private function searchAllPaths():void {
            foundGames = [];
            var log:String = "البحث في المسارات:\n";
            writeLog("--- بدء البحث عن الألعاب ---");

            for each (var path:String in SEARCH_PATHS) {
                try {
                    var folder:File = new File(path);
                    log += "\n• " + path + "\n";

                    if (!folder.exists) {
                        log += "  → غير موجود\n";
                        writeLog("PATH NOT FOUND: " + path);
                        continue;
                    }

                    var files:Array = folder.getDirectoryListing();
                    var count:int = 0;
                    for each (var f:File in files) {
                        if (f.extension && f.extension.toLowerCase() == "swf") {
                            foundGames.push(f);
                            count++;
                            log += "  ✅ " + f.name + " (" + Math.round(f.size/1024) + "KB)\n";
                            writeLog("FOUND: " + f.nativePath);
                        }
                    }
                    if (count == 0) {
                        log += "  → لا يوجد SWF\n";
                    }
                } catch (err:Error) {
                    log += "  ❌ خطأ: " + err.message + "\n";
                    writeLog("SEARCH ERROR in " + path + ": " + err.message);
                }
            }

            statusText.text = log;

            if (foundGames.length == 1) {
                statusText.appendText("\nتشغيل تلقائي: " + foundGames[0].name);
                writeLog("تشغيل تلقائي: " + foundGames[0].nativePath);
                launchGame(foundGames[0]);
            } else if (foundGames.length > 1) {
                showGameList();
            } else {
                statusText.appendText(
                    "\n\nلم يتم العثور على ألعاب.\n" +
                    "ضع ملف SWF في:\n" + SEARCH_PATHS[0] +
                    "\nأو استخدم زر الاستيراد."
                );
                writeLog("لم يتم العثور على أي لعبة.");
            }
        }

        private function showGameList():void {
            clearGameButtons();
            statusText.text = "تم العثور على " + foundGames.length + " لعبة:";
            var startY:Number = 320;
            var limit:int = Math.min(foundGames.length, 8);
            for (var i:int = 0; i < limit; i++) {
                var btn:Sprite = makeGameBtn(foundGames[i], startY + i * 85);
                uiContainer.addChild(btn);
            }
        }

        // ============================================================
        // GAME BUTTON
        // ============================================================
        private function makeGameBtn(f:File, y:Number,
                                     isDirectoryMode:Boolean = false,
                                     isUpAction:Boolean = false):Sprite {
            var w:Number = SW - 40;
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0x0D1F0D);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.graphics.endFill();
            btn.graphics.lineStyle(1, 0x00AA00);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.x = 20;
            btn.y = y;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 20, 0x00FF00);
            lbl.defaultTextFormat = fmt;

            if (isUpAction) {
                lbl.text = "📁 .. (العودة للخلف)";
            } else if (isDirectoryMode) {
                lbl.text = "📁 " + f.name;
            } else {
                var sizeMB:Number = Math.round(f.size / 1024 / 1024 * 10) / 10;
                lbl.text = "▶  " + f.name.replace(/\.swf$/i, "") + "  [" + sizeMB + "MB]";
            }

            lbl.width  = w - 20;
            lbl.height = 40;
            lbl.x = 10;
            lbl.y = 15;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);

            btn.useHandCursor = true;
            btn.buttonMode    = true;

            // حفظ مرجع f محلياً للـ closure
            var targetFile:File = f;
            var dirMode:Boolean = isDirectoryMode;
            var upMode:Boolean  = isUpAction;

            btn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                if (upMode || dirMode) {
                    browseDirectory(targetFile);
                } else {
                    launchGame(targetFile);
                }
            });
            return btn;
        }

        // ============================================================
        // INVOKE — يُستدعى عند فتح ملف SWF أو مشاركته
        // ============================================================
        private function onInvoke(e:InvokeEvent):void {
            writeLog("onInvoke: args=" + e.arguments.length);

            if (e.arguments && e.arguments.length > 0) {
                var raw:String = String(e.arguments[0]);
                writeLog("onInvoke raw arg: " + raw);

                // تنظيف المسار
                var path:String = raw;
                if (path.indexOf("file://") == 0) path = decodeURIComponent(path.substring(7));
                else if (path.indexOf("content://") == 0) {
                    // content URI — نحاول نسخه إلى مؤقت
                    path = copyContentUriToTemp(raw);
                }

                writeLog("onInvoke path after clean: " + path);

                if (path != null && path.length > 0) {
                    try {
                        var f:File = new File(path);
                        if (f.exists) {
                            writeLog("onInvoke: الملف موجود، تشغيل...");
                            launchGame(f);
                            return;
                        } else {
                            writeLog("onInvoke: الملف غير موجود: " + path);
                        }
                    } catch (err:Error) {
                        writeLog("onInvoke ERROR: " + err.message);
                    }
                }
            }

            // إن لم يكن هناك ملف محدد
            if (uiContainer.visible) {
                searchAllPaths();
            }
        }

        // معالجة content:// URI — ينسخ الملف إلى مؤقت
        private function copyContentUriToTemp(uri:String):String {
            try {
                writeLog("محاولة نسخ content URI: " + uri);
                var req:URLRequest = new URLRequest(uri);
                // AIR لا يدعم قراءة content URI مباشرة، نُعيد null
                writeLog("content URI غير مدعوم مباشرة في AIR");
                return null;
            } catch (err:Error) {
                writeLog("copyContentUri ERROR: " + err.message);
                return null;
            }
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
            writeLog("browseDirectory: " + dir.nativePath);

            try {
                var files:Array = dir.getDirectoryListing();
                // ترتيب: مجلدات أولاً ثم SWF
                files.sortOn("name");

                var startY:Number = 320;
                var count:int     = 0;

                // زر العودة
                if (dir.parent) {
                    uiContainer.addChild(makeGameBtn(dir.parent, startY, false, true));
                    startY += 85;
                    count++;
                }

                for each (var f:File in files) {
                    if (count >= 30) break;
                    if (f.isDirectory && f.name.indexOf(".") != 0) {
                        uiContainer.addChild(makeGameBtn(f, startY, true, false));
                        startY += 85; count++;
                    } else if (f.extension && f.extension.toLowerCase() == "swf") {
                        uiContainer.addChild(makeGameBtn(f, startY, false, false));
                        startY += 85; count++;
                    }
                }

                if (count == (dir.parent ? 1 : 0)) {
                    statusText.text += "\n\nهذا المجلد فارغ.";
                }
            } catch (err:Error) {
                statusText.text = "❌ خطأ في قراءة المسار: " + err.message;
                writeLog("browseDirectory ERROR: " + err.message);
            }
        }

        // ============================================================
        // LAUNCH GAME — الأهم، مع كل إصلاحات الشاشة السوداء
        // ============================================================
        private function launchGame(f:File):void {
            writeLog("=== launchGame: " + f.nativePath + " (" + f.size + " bytes) ===");

            try {
                // قراءة الملف
                var stream:FileStream = new FileStream();
                stream.open(f, FileMode.READ);
                var bytes:ByteArray = new ByteArray();
                stream.readBytes(bytes);
                stream.close();

                writeLog("تم قراءة الملف: " + bytes.length + " bytes");

                // التحقق من توقيع SWF
                bytes.position = 0;
                var sig:String = "";
                for (var i:int = 0; i < Math.min(3, bytes.length); i++) {
                    sig += String.fromCharCode(bytes[i]);
                }
                writeLog("SWF signature: " + sig);

                if (sig != "CWS" && sig != "FWS" && sig != "ZWS") {
                    writeLog("❌ ليس ملف SWF صالح! التوقيع: " + sig);
                    statusText.text = "❌ الملف ليس SWF صالح.\nالتوقيع: " + sig;
                    uiContainer.visible = true;
                    return;
                }

                // تنظيف الـ loader القديم
                destroyLoader();

                // إخفاء الواجهة
                uiContainer.visible = false;

                // إنشاء Loader جديد
                gameLoader = new Loader();
                gameLoader.contentLoaderInfo.addEventListener(Event.INIT,       onGameInit);
                gameLoader.contentLoaderInfo.addEventListener(Event.COMPLETE,   onGameComplete);
                gameLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                gameLoader.contentLoaderInfo.addEventListener(ErrorEvent.ERROR,      onLoadError);

                // إضافة قبل التحميل
                addChildAt(gameLoader, 0);

                var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
                ctx.allowCodeImport = true;

                bytes.position = 0;
                gameLoader.loadBytes(bytes, ctx);

                writeLog("loadBytes بدأ...");

            } catch (err:Error) {
                uiContainer.visible = true;
                statusText.text = "❌ خطأ تشغيل: " + err.message;
                writeLog("launchGame EXCEPTION: " + err.message + "\n" + err.getStackTrace());
            }
        }

        private function destroyLoader():void {
            if (gameLoader) {
                try {
                    gameLoader.contentLoaderInfo.removeEventListener(Event.INIT,       onGameInit);
                    gameLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE,   onGameComplete);
                    gameLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                    gameLoader.contentLoaderInfo.removeEventListener(ErrorEvent.ERROR,      onLoadError);
                    if (contains(gameLoader)) removeChild(gameLoader);
                    gameLoader.unloadAndStop(true);
                } catch (e:Error) {
                    writeLog("destroyLoader error: " + e.message);
                }
                gameLoader = null;
            }
        }

        // يُستدعى عند اكتمال تحميل الهيكل الأساسي للـ SWF
        private function onGameInit(e:Event):void {
            writeLog("onGameInit: " +
                gameLoader.contentLoaderInfo.width + "x" +
                gameLoader.contentLoaderInfo.height +
                " frameRate=" + gameLoader.contentLoaderInfo.frameRate);
            positionGame();
        }

        // يُستدعى عند اكتمال التحميل الكامل
        private function onGameComplete(e:Event):void {
            writeLog("onGameComplete — اللعبة اكتملت.");
            positionGame();
        }

        // ============================================================
        // POSITION GAME — إصلاح الشاشة السوداء
        // ============================================================
        private function positionGame():void {
            if (!gameLoader) return;

            var info:* = gameLoader.contentLoaderInfo;
            var swfW:Number = info.width  > 0 ? info.width  : 550;
            var swfH:Number = info.height > 0 ? info.height : 400;

            // أبعاد الشاشة المحدّثة
            var scrW:Number = stage.stageWidth  > 0 ? stage.stageWidth  : SW;
            var scrH:Number = stage.stageHeight > 0 ? stage.stageHeight : SH;

            // نسبة التكبير للملء مع الحفاظ على النسبة
            var scale:Number = Math.min(scrW / swfW, scrH / swfH);

            gameLoader.scaleX = scale;
            gameLoader.scaleY = scale;
            gameLoader.x = Math.round((scrW - swfW * scale) / 2);
            gameLoader.y = Math.round((scrH - swfH * scale) / 2);

            writeLog("positionGame: swf=" + swfW + "x" + swfH +
                     " screen=" + scrW + "x" + scrH +
                     " scale=" + scale.toFixed(3) +
                     " pos=(" + gameLoader.x + "," + gameLoader.y + ")");

            // التأكد أن الـ loader فوق الخلفية وتحت الـ uiContainer
            var loaderIndex:int = getChildIndex(gameLoader);
            var bgIndex:int     = 0; // الخلفية دائماً index 0
            if (loaderIndex <= bgIndex) {
                setChildIndex(gameLoader, 1);
            }
        }

        // ============================================================
        // ERROR HANDLERS
        // ============================================================
        private function onLoadError(e:*):void {
            var msg:String = (e is IOErrorEvent) ? (e as IOErrorEvent).text : String(e);
            writeLog("❌ onLoadError: " + msg);
            uiContainer.visible = true;
            statusText.text = "❌ فشل تحميل اللعبة:\n" + msg +
                              "\n\nتحقق من سجل الأخطاء في:\n/sdcard/NostaGames/logs/";
            destroyLoader();
        }

        private function onUncaughtError(e:UncaughtErrorEvent):void {
            var msg:String = "";
            if (e.error is Error)       msg = (e.error as Error).getStackTrace();
            else if (e.error is ErrorEvent) msg = (e.error as ErrorEvent).text;
            else msg = String(e.error);
            writeLog("!!! UncaughtError: " + msg);
            e.preventDefault();
        }

        // ============================================================
        // EXIT — حفظ السجل + نسخ للـ Clipboard
        // ============================================================
        private function onExiting(e:Event):void {
            writeLog("=== التطبيق يُغلق ===");
            flushLogToFile();
            copyLogToClipboard();
        }

        // ============================================================
        // LOG SYSTEM
        // ============================================================
        private function writeLog(msg:String):void {
            var now:Date    = new Date();
            var timestamp:String = now.getHours() + ":" +
                pad2(now.getMinutes()) + ":" +
                pad2(now.getSeconds());
            var line:String = "[" + timestamp + "] " + msg;
            logLines.push(line);

            // حفظ فوري كل 10 سطور
            if (logLines.length % 10 == 0) {
                flushLogToFile();
            }
        }

        private function flushLogToFile():void {
            try {
                var logsDir:File = new File("/sdcard/NostaGames/logs/");
                if (!logsDir.exists) logsDir.createDirectory();

                var stream:FileStream = new FileStream();
                stream.open(logFile, FileMode.WRITE);
                stream.writeUTFBytes(logLines.join("\n") + "\n");
                stream.close();
            } catch (err:Error) {
                // لا نستطيع كتابة سجل هنا لتجنب التكرار اللانهائي
            }
        }

        private function copyLogToClipboard():void {
            try {
                var fullLog:String = "=== Nosta Flash Player Log ===\n" +
                                     logLines.join("\n");
                Clipboard.generalClipboard.clear();
                Clipboard.generalClipboard.setData(ClipboardFormats.TEXT_FORMAT, fullLog);
            } catch (err:Error) {}
        }

        private function pad2(n:int):String {
            return n < 10 ? "0" + n : String(n);
        }
    }
}
