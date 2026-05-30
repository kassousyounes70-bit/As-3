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
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.utils.ByteArray;

    public class Main extends Sprite {

        // ── المجلد المشترك مع التطبيق الرئيسي ──
        // التطبيق الرئيسي com.ncore.nostagames يحفظ SWF هنا
        private static const SHARED_FOLDER:String = "/sdcard/Android/data/com.ncore.nostagames/files/flash_games/";
        private static const QUEUE_FILE:String    = SHARED_FOLDER + ".queue"; // اسم اللعبة المطلوب تشغيلها

        private var browseButton:Sprite;
        private var statusText:TextField;
        private var fileToLoad:File;
        private var gameLoader:Loader;

        public function Main() {
            stage.align     = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;

            // خلفية
            graphics.beginFill(0x0A0A0A);
            graphics.drawRect(0, 0, 2500, 2500);
            graphics.endFill();

            buildUI();

            // استمع لـ Invoke (من التطبيق الرئيسي)
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);

            // تحقق من المجلد المشترك عند الفتح
            checkSharedFolder();
        }

        // ── بناء الواجهة ──
        private function buildUI():void {

            // عنوان
            var title:TextField = new TextField();
            var titleFmt:TextFormat = new TextFormat("_sans", 32, 0x00FF00, true);
            titleFmt.align = TextFormatAlign.CENTER;
            title.defaultTextFormat = titleFmt;
            title.text = "⚡ NOSTA FLASH PLAYER";
            title.width = stage.stageWidth;
            title.height = 50;
            title.x = 0;
            title.y = 30;
            title.mouseEnabled = false;
            addChild(title);

            // زر الاستيراد اليدوي
            browseButton = new Sprite();
            browseButton.graphics.beginFill(0x1A6B1A);
            browseButton.graphics.drawRoundRect(0, 0, 320, 90, 20);
            browseButton.graphics.endFill();
            browseButton.graphics.lineStyle(2, 0x00FF00);
            browseButton.graphics.drawRoundRect(0, 0, 320, 90, 20);
            browseButton.x = (stage.stageWidth - 320) / 2;
            browseButton.y = 120;

            var btnText:TextField = new TextField();
            var btnFmt:TextFormat = new TextFormat("_sans", 26, 0xFFFFFF, true);
            btnFmt.align = TextFormatAlign.CENTER;
            btnText.defaultTextFormat = btnFmt;
            btnText.text = "📂 استيراد SWF";
            btnText.width = 320;
            btnText.height = 50;
            btnText.y = 20;
            btnText.mouseEnabled = false;
            browseButton.addChild(btnText);
            addChild(browseButton);
            browseButton.addEventListener(MouseEvent.CLICK, onBrowseClick);

            // نص الحالة
            statusText = new TextField();
            var statusFmt:TextFormat = new TextFormat("_sans", 20, 0x888888);
            statusText.defaultTextFormat = statusFmt;
            statusText.width  = stage.stageWidth - 40;
            statusText.height = stage.stageHeight - 260;
            statusText.x = 20;
            statusText.y = 240;
            statusText.multiline = true;
            statusText.wordWrap  = true;
            statusText.text = "جاري التحقق من الألعاب المتاحة...";
            addChild(statusText);
        }

        // ── التحقق من المجلد المشترك ──
        private function checkSharedFolder():void {
            try {
                // أولاً: هل يوجد ملف قائمة انتظار؟ (التطبيق الرئيسي يكتب اسم اللعبة هنا)
                var queueFile:File = new File(QUEUE_FILE);
                if (queueFile.exists) {
                    var stream:FileStream = new FileStream();
                    stream.open(queueFile, FileMode.READ);
                    var gameName:String = stream.readUTFBytes(stream.bytesAvailable).replace(/[\r\n]/g, "");
                    stream.close();

                    if (gameName.length > 0) {
                        var targetSwf:File = new File(SHARED_FOLDER + gameName);
                        if (targetSwf.exists) {
                            statusText.text = "🎮 جاري تشغيل: " + gameName;
                            // احذف ملف القائمة بعد القراءة
                            queueFile.deleteFile();
                            injectPayload(targetSwf);
                            return;
                        }
                    }
                }

                // ثانياً: هل يوجد SWF واحد في المجلد؟
                var folder:File = new File(SHARED_FOLDER);
                if (folder.exists) {
                    var files:Array = folder.getDirectoryListing();
                    var swfFiles:Array = [];
                    for each (var f:File in files) {
                        if (f.extension && f.extension.toLowerCase() == "swf") {
                            swfFiles.push(f);
                        }
                    }

                    if (swfFiles.length == 1) {
                        // لعبة واحدة — شغّلها مباشرة
                        statusText.text = "🎮 تم العثور على: " + swfFiles[0].name;
                        injectPayload(swfFiles[0]);
                    } else if (swfFiles.length > 1) {
                        // ألعاب متعددة — أظهر قائمة اختيار
                        showGameList(swfFiles);
                    } else {
                        statusText.text = "لا توجد ألعاب في المجلد المشترك.\nاستخدم زر الاستيراد أو أرسل لعبة من التطبيق الرئيسي.";
                    }
                } else {
                    statusText.text = "المجلد المشترك غير موجود بعد.\nاستخدم زر الاستيراد يدوياً.";
                }

            } catch (error:Error) {
                statusText.text = "خطأ في قراءة المجلد: " + error.message;
            }
        }

        // ── عرض قائمة الألعاب إذا وجد أكثر من واحدة ──
        private function showGameList(files:Array):void {
            statusText.text = "اختر لعبة:\n";
            var startY:Number = 240;

            for (var i:int = 0; i < files.length && i < 8; i++) {
                var gameFile:File = files[i];
                var btn:Sprite = createGameButton(gameFile, startY + (i * 80));
                addChild(btn);
            }
        }

        private function createGameButton(gameFile:File, yPos:Number):Sprite {
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0x1A2A1A);
            btn.graphics.drawRoundRect(0, 0, stage.stageWidth - 40, 65, 10);
            btn.graphics.endFill();
            btn.graphics.lineStyle(1, 0x00AA00);
            btn.graphics.drawRoundRect(0, 0, stage.stageWidth - 40, 65, 10);
            btn.x = 20;
            btn.y = yPos;

            var label:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 22, 0x00FF00);
            label.defaultTextFormat = fmt;
            label.text = "▶ " + gameFile.name.replace(".swf", "").replace(".SWF", "");
            label.width  = stage.stageWidth - 60;
            label.height = 40;
            label.x = 10;
            label.y = 12;
            label.mouseEnabled = false;
            btn.addChild(label);

            btn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                injectPayload(gameFile);
            });

            return btn;
        }

        // ── استقبال Invoke من التطبيق الرئيسي ──
        private function onInvoke(e:InvokeEvent):void {
            if (e.arguments && e.arguments.length > 0) {
                var filePath:String = e.arguments[0] as String;
                try {
                    var sharedFile:File = new File(filePath);
                    if (sharedFile.exists) {
                        injectPayload(sharedFile);
                    } else {
                        statusText.text = "الملف غير موجود: " + filePath;
                    }
                } catch (error:Error) {
                    statusText.text = "خطأ في المسار: " + error.message;
                }
            } else {
                // فُتح بدون arguments — تحقق من المجلد المشترك
                checkSharedFolder();
            }
        }

        // ── استيراد يدوي ──
        private function onBrowseClick(e:MouseEvent):void {
            fileToLoad = new File();
            fileToLoad.addEventListener(Event.SELECT, onFileSelected);
            fileToLoad.browseForOpen("اختر ملف SWF");
        }

        private function onFileSelected(e:Event):void {
            statusText.text = "تم الاختيار: " + fileToLoad.name;
            injectPayload(fileToLoad);
        }

        // ── تشغيل اللعبة ──
        private function injectPayload(targetFile:File):void {
            try {
                var stream:FileStream = new FileStream();
                stream.open(targetFile, FileMode.READ);
                var fileData:ByteArray = new ByteArray();
                stream.readBytes(fileData);
                stream.close();

                // إزالة المحتوى السابق
                if (gameLoader != null) {
                    if (contains(gameLoader)) removeChild(gameLoader);
                    gameLoader.unloadAndStop();
                    gameLoader = null;
                }

                // إخفاء الواجهة
                browseButton.visible = false;
                statusText.visible   = false;

                // تشغيل اللعبة
                gameLoader = new Loader();
                gameLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                addChild(gameLoader);

                var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
                context.allowCodeImport = true;
                gameLoader.loadBytes(fileData, context);

            } catch (error:Error) {
                statusText.visible = true;
                statusText.text = "خطأ في التشغيل: " + error.message;
            }
        }

        private function onLoadError(e:IOErrorEvent):void {
            browseButton.visible = true;
            statusText.visible   = true;
            statusText.text = "❌ فشل تحميل اللعبة: " + e.text;
        }
    }
}
