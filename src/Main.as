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
    import flash.net.FileFilter;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.utils.ByteArray;

    public class Main extends Sprite {

        // مسارات البحث عن ملفات SWF
        private static const SEARCH_PATHS:Array = [
            // مجلد التطبيق الرئيسي المشترك
            "/sdcard/Android/data/com.ncore.nostagames/files/flash_games/",
            // مجلد التطبيق نفسه
            File.applicationStorageDirectory.nativePath + "/flash_games/",
            // مجلد Downloads
            "/sdcard/Download/",
            // مجلد الجذر
            "/sdcard/"
        ];

        private var statusText:TextField;
        private var gameLoader:Loader;
        private var uiContainer:Sprite;
        private var foundGames:Array = [];

        public function Main() {
            stage.align     = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;

            graphics.beginFill(0x0A0A0A);
            graphics.drawRect(0, 0, 4000, 4000);
            graphics.endFill();

            uiContainer = new Sprite();
            addChild(uiContainer);

            buildUI();

            NativeApplication.nativeApplication.addEventListener(
                InvokeEvent.INVOKE, onInvoke);

            // ابدأ البحث فوراً
            searchAllPaths();
        }

        private function buildUI():void {
            var title:TextField = new TextField();
            var tf:TextFormat = new TextFormat("_sans", 26, 0x00FF00, true);
            tf.align = TextFormatAlign.CENTER;
            title.defaultTextFormat = tf;
            title.text = "NOSTA FLASH PLAYER";
            title.width  = stage.stageWidth || 1920;
            title.height = 50;
            title.x = 0;
            title.y = 30;
            title.mouseEnabled = false;
            uiContainer.addChild(title);

            // زر تحديث البحث
            var refreshBtn:Sprite = makeButton("🔄 بحث عن ألعاب", 0x1A4A6B, 100);
            refreshBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                clearUI();
                searchAllPaths();
            });
            uiContainer.addChild(refreshBtn);

            // زر استيراد يدوي
            var browseBtn:Sprite = makeButton("📂 استيراد SWF يدوياً", 0x1A6B1A, 210);
            browseBtn.addEventListener(MouseEvent.CLICK, onBrowseClick);
            uiContainer.addChild(browseBtn);

            // نص الحالة
            statusText = new TextField();
            var stf:TextFormat = new TextFormat("_sans", 16, 0x888888);
            statusText.defaultTextFormat = stf;
            statusText.width   = (stage.stageWidth || 1920) - 40;
            statusText.height  = 400;
            statusText.x = 20;
            statusText.y = 320;
            statusText.multiline = true;
            statusText.wordWrap  = true;
            statusText.text = "جاري البحث...";
            uiContainer.addChild(statusText);
        }

        private function makeButton(label:String, color:uint, yPos:Number):Sprite {
            var w:Number = Math.min((stage.stageWidth || 1920) - 80, 500);
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(color);
            btn.graphics.drawRoundRect(0, 0, w, 80, 14);
            btn.graphics.endFill();
            btn.graphics.lineStyle(2, 0x00FF00);
            btn.graphics.drawRoundRect(0, 0, w, 80, 14);
            btn.x = ((stage.stageWidth || 1920) - w) / 2;
            btn.y = yPos;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 22, 0xFFFFFF, true);
            fmt.align = TextFormatAlign.CENTER;
            lbl.defaultTextFormat = fmt;
            lbl.text = label;
            lbl.width = w;
            lbl.height = 45;
            lbl.y = 18;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);
            return btn;
        }

        // ── البحث في كل المسارات ──
        private function searchAllPaths():void {
            foundGames = [];
            var log:String = "البحث في المسارات:\n";

            for each (var path:String in SEARCH_PATHS) {
                try {
                    var folder:File = new File(path);
                    log += "\n• " + path + "\n";

                    if (!folder.exists) {
                        log += "  → غير موجود\n";
                        continue;
                    }

                    var files:Array = folder.getDirectoryListing();
                    var count:int = 0;
                    for each (var f:File in files) {
                        if (f.extension && f.extension.toLowerCase() == "swf") {
                            foundGames.push(f);
                            count++;
                            log += "  ✅ " + f.name + " (" + Math.round(f.size/1024) + "KB)\n";
                        }
                    }
                    if (count == 0) log += "  → لا يوجد SWF\n";

                } catch (err:Error) {
                    log += "  ❌ خطأ: " + err.message + "\n";
                }
            }

            statusText.text = log;

            if (foundGames.length == 1) {
                // لعبة واحدة — شغّلها مباشرة
                statusText.appendText("\nتشغيل تلقائي: " + foundGames[0].name);
                launchGame(foundGames[0]);
            } else if (foundGames.length > 1) {
                showGameList();
            } else {
                statusText.appendText("\n\nلم يتم العثور على ألعاب.\n");
                statusText.appendText("ضع ملف SWF في:\n");
                statusText.appendText(SEARCH_PATHS[0] + "\n");
                statusText.appendText("أو استخدم زر الاستيراد.");
            }
        }

        private function clearUI():void {
            // احذف بطاقات الألعاب القديمة
            while (uiContainer.numChildren > 4) {
                uiContainer.removeChildAt(4);
            }
        }

        private function showGameList():void {
            statusText.text = "تم العثور على " + foundGames.length + " لعبة:";
            var startY:Number = 320;
            for (var i:int = 0; i < foundGames.length && i < 8; i++) {
                var btn:Sprite = makeGameBtn(foundGames[i], startY + i * 85);
                uiContainer.addChild(btn);
            }
        }

        private function makeGameBtn(f:File, y:Number):Sprite {
            var w:Number = (stage.stageWidth || 1920) - 40;
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0x0D1F0D);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.graphics.endFill();
            btn.graphics.lineStyle(1, 0x00AA00);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.x = 20; btn.y = y;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 20, 0x00FF00);
            lbl.defaultTextFormat = fmt;
            lbl.text = "▶  " + f.name.replace(/\.swf$/i, "") +
                       "  [" + Math.round(f.size/1024/1024*10)/10 + "MB]";
            lbl.width = w - 20; lbl.height = 40;
            lbl.x = 10; lbl.y = 15;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);

            btn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                launchGame(f);
            });
            return btn;
        }

        // ── Invoke من التطبيق الرئيسي ──
        private function onInvoke(e:InvokeEvent):void {
            if (e.arguments && e.arguments.length > 0) {
                var path:String = e.arguments[0];
                if (path.indexOf("file://") == 0) path = path.substring(7);
                try {
                    var f:File = new File(path);
                    if (f.exists) { launchGame(f); return; }
                } catch (err:Error) {}
            }
            searchAllPaths();
        }

        // ── استيراد يدوي ──
        private function onBrowseClick(e:MouseEvent):void {
            try {
                var picker:File = new File();
                picker.addEventListener(Event.SELECT, function(ev:Event):void {
                    launchGame(picker);
                });
                picker.addEventListener(Event.CANCEL, function(ev:Event):void {
                    statusText.text = "تم الإلغاء.";
                });
                picker.browseForOpen("اختر ملف SWF", [
                    new flash.net.FileFilter("Flash Games", "*.swf")
                ]);
            } catch (err:Error) {
                statusText.text = "خطأ في فتح المستعرض: " + err.message +
                    "\n\nضع ملف SWF في:\n" + SEARCH_PATHS[0] +
                    "\nثم اضغط 'بحث عن ألعاب'";
            }
        }

        // ── تشغيل اللعبة ──
        private function launchGame(f:File):void {
            try {
                statusText.text = "جاري تحميل: " + f.name;

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
                statusText.text = "❌ خطأ تشغيل: " + err.message;
            }
        }

        private function onError(e:IOErrorEvent):void {
            uiContainer.visible = true;
            statusText.text = "❌ فشل التحميل: " + e.text;
        }
    }
}
