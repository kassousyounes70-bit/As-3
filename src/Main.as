package {
    import flash.desktop.NativeApplication;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.InvokeEvent;
    import flash.events.MouseEvent;
    import flash.events.IOErrorEvent;
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

        // المجلد المشترك مع التطبيق الرئيسي
        private static const SHARED_FOLDER:String =
            "/sdcard/Android/data/com.ncore.nostagames/files/flash_games/";
        private static const QUEUE_FILE:String = SHARED_FOLDER + ".queue";

        private var browseButton:Sprite;
        private var statusText:TextField;
        private var gameLoader:Loader;
        private var uiContainer:Sprite;

        public function Main() {
            stage.align     = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;

            graphics.beginFill(0x0A0A0A);
            graphics.drawRect(0, 0, 2500, 2500);
            graphics.endFill();

            uiContainer = new Sprite();
            addChild(uiContainer);

            buildUI();

            NativeApplication.nativeApplication.addEventListener(
                InvokeEvent.INVOKE, onInvoke);
        }

        private function buildUI():void {
            // عنوان
            var title:TextField = new TextField();
            var tf:TextFormat = new TextFormat("_sans", 28, 0x00FF00, true);
            tf.align = TextFormatAlign.CENTER;
            title.defaultTextFormat = tf;
            title.text = "NOSTA FLASH PLAYER";
            title.width  = 800;
            title.height = 50;
            title.x = (stage.stageWidth - 800) / 2;
            title.y = 40;
            title.mouseEnabled = false;
            uiContainer.addChild(title);

            // زر استيراد
            browseButton = new Sprite();
            browseButton.graphics.beginFill(0x1A6B1A);
            browseButton.graphics.drawRoundRect(0, 0, 340, 90, 16);
            browseButton.graphics.endFill();
            browseButton.graphics.lineStyle(2, 0x00FF00);
            browseButton.graphics.drawRoundRect(0, 0, 340, 90, 16);
            browseButton.x = (stage.stageWidth - 340) / 2;
            browseButton.y = 120;

            var btnTf:TextFormat = new TextFormat("_sans", 24, 0xFFFFFF, true);
            btnTf.align = TextFormatAlign.CENTER;
            var btnLabel:TextField = new TextField();
            btnLabel.defaultTextFormat = btnTf;
            btnLabel.text = "استيراد ملف SWF";
            btnLabel.width  = 340;
            btnLabel.height = 50;
            btnLabel.y = 20;
            btnLabel.mouseEnabled = false;
            browseButton.addChild(btnLabel);
            browseButton.addEventListener(MouseEvent.CLICK, onBrowseClick);
            uiContainer.addChild(browseButton);

            // نص الحالة
            statusText = new TextField();
            var stf:TextFormat = new TextFormat("_sans", 18, 0x888888);
            statusText.defaultTextFormat = stf;
            statusText.width   = stage.stageWidth - 40;
            statusText.height  = 300;
            statusText.x = 20;
            statusText.y = 240;
            statusText.multiline = true;
            statusText.wordWrap  = true;
            statusText.text = "جاهز — في انتظار لعبة...";
            uiContainer.addChild(statusText);
        }

        // ── Invoke: نقطة الدخول الرئيسية ──
        private function onInvoke(e:InvokeEvent):void {
            statusText.text = "Invoke: args=" + e.arguments.length;

            if (e.arguments && e.arguments.length > 0) {
                // جاء بمسار ملف مباشر (من التطبيق الرئيسي أو فتح ملف)
                var path:String = e.arguments[0];
                statusText.appendText("\nPath: " + path);
                loadFromPath(path);
            } else {
                // فُتح بدون arguments — تحقق من المجلد المشترك
                checkSharedFolder();
            }
        }

        // ── قراءة ملف من مسار ──
        private function loadFromPath(path:String):void {
            try {
                // نظف المسار من file:// إذا وجد
                if (path.indexOf("file://") == 0) {
                    path = path.substring(7);
                }
                var f:File = new File(path);
                if (f.exists) {
                    launchGame(f);
                } else {
                    statusText.text = "الملف غير موجود: " + path;
                    checkSharedFolder();
                }
            } catch (err:Error) {
                statusText.text = "خطأ مسار: " + err.message;
                checkSharedFolder();
            }
        }

        // ── فحص المجلد المشترك ──
        private function checkSharedFolder():void {
            try {
                // أولاً: ملف queue من التطبيق الرئيسي
                var qf:File = new File(QUEUE_FILE);
                if (qf.exists) {
                    var s:FileStream = new FileStream();
                    s.open(qf, FileMode.READ);
                    var name:String = s.readUTFBytes(s.bytesAvailable).replace(/[\r\n\s]/g, "");
                    s.close();
                    if (name.length > 0) {
                        var target:File = new File(SHARED_FOLDER + name);
                        if (target.exists) {
                            qf.deleteFile();
                            launchGame(target);
                            return;
                        }
                    }
                }

                // ثانياً: بحث في المجلد
                var folder:File = new File(SHARED_FOLDER);
                if (!folder.exists) {
                    statusText.text = "المجلد المشترك غير موجود.\nاستخدم زر الاستيراد.";
                    return;
                }

                var files:Array  = folder.getDirectoryListing();
                var swfs:Array   = [];
                for each (var f:File in files) {
                    if (f.extension && f.extension.toLowerCase() == "swf") swfs.push(f);
                }

                if (swfs.length == 1) {
                    launchGame(swfs[0]);
                } else if (swfs.length > 1) {
                    showList(swfs);
                } else {
                    statusText.text = "لا توجد ألعاب.\nاستخدم زر الاستيراد أو أرسل من التطبيق الرئيسي.";
                }

            } catch (err:Error) {
                statusText.text = "خطأ: " + err.message;
            }
        }

        // ── قائمة اختيار عند وجود أكثر من لعبة ──
        private function showList(swfs:Array):void {
            statusText.text = "اختر لعبة:";
            for (var i:int = 0; i < swfs.length && i < 6; i++) {
                var btn:Sprite = makeListBtn(swfs[i], 240 + i * 75);
                uiContainer.addChild(btn);
            }
        }

        private function makeListBtn(f:File, y:Number):Sprite {
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0x111811);
            btn.graphics.drawRoundRect(0, 0, stage.stageWidth - 40, 60, 8);
            btn.graphics.endFill();
            btn.graphics.lineStyle(1, 0x006600);
            btn.graphics.drawRoundRect(0, 0, stage.stageWidth - 40, 60, 8);
            btn.x = 20; btn.y = y;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 20, 0x00FF00);
            lbl.defaultTextFormat = fmt;
            lbl.text = "▶  " + f.name.replace(/\.swf$/i, "");
            lbl.width = stage.stageWidth - 60;
            lbl.height = 35; lbl.x = 10; lbl.y = 12;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);

            btn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                launchGame(f);
            });
            return btn;
        }

        // ── استيراد يدوي ──
        private function onBrowseClick(e:MouseEvent):void {
            var picker:File = new File();
            picker.addEventListener(Event.SELECT, function(ev:Event):void {
                launchGame(picker);
            });
            picker.browseForOpen("اختر ملف SWF");
        }

        // ── تشغيل اللعبة ──
        private function launchGame(f:File):void {
            statusText.text = "جاري تشغيل: " + f.name;
            try {
                var stream:FileStream = new FileStream();
                stream.open(f, FileMode.READ);
                var bytes:ByteArray = new ByteArray();
                stream.readBytes(bytes);
                stream.close();

                if (gameLoader) {
                    if (contains(gameLoader)) removeChild(gameLoader);
                    gameLoader.unloadAndStop();
                    gameLoader = null;
                }

                uiContainer.visible = false;

                gameLoader = new Loader();
                gameLoader.contentLoaderInfo.addEventListener(
                    IOErrorEvent.IO_ERROR, onError);
                addChild(gameLoader);

                var ctx:LoaderContext = new LoaderContext(
                    false, ApplicationDomain.currentDomain);
                ctx.allowCodeImport = true;
                gameLoader.loadBytes(bytes, ctx);

            } catch (err:Error) {
                uiContainer.visible = true;
                statusText.text = "خطأ تشغيل: " + err.message;
            }
        }

        private function onError(e:IOErrorEvent):void {
            uiContainer.visible = true;
            statusText.text = "فشل التحميل: " + e.text;
        }
    }
}
