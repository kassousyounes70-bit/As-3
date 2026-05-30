package {
    import flash.desktop.NativeApplication;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.InvokeEvent;
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.events.KeyboardEvent;
    import flash.events.IOErrorEvent;
    import flash.events.PermissionEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.utils.ByteArray;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.ui.Keyboard;

    public class Main extends Sprite {

        private static const SEARCH_PATHS:Array = [
            "/sdcard/NostaGames/",
            "/sdcard/Android/data/com.ncore.nostagames/files/flash_games/",
            File.applicationStorageDirectory.nativePath + "/flash_games/",
            "/sdcard/Download/",
            "/sdcard/"
        ];

        private static const XOR_KEY:String = "YounesXorEntanglementKey2026";
        private static const B64_CHARS:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        private static const KEY_MAP:Object = {
            "SPACE": Keyboard.SPACE,
            "W": Keyboard.W,
            "A": Keyboard.A,
            "S": Keyboard.S,
            "D": Keyboard.D,
            "UP": Keyboard.UP,
            "DOWN": Keyboard.DOWN,
            "LEFT": Keyboard.LEFT,
            "RIGHT": Keyboard.RIGHT,
            "ENTER": Keyboard.ENTER
        };

        private var statusText:TextField;
        private var gameLoader:Loader;
        private var uiContainer:Sprite;
        private var gamepadLayer:Sprite;
        private var foundGames:Array = [];
        private var base64Lookup:Array;
        private var currentControlsData:Object;

        public function Main() {
            stage.align = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            
            Multitouch.inputMode = MultitouchInputMode.TOUCH_POINT;

            graphics.beginFill(0x0A0A0A);
            graphics.drawRect(0, 0, 4000, 4000);
            graphics.endFill();

            initCrypto();

            uiContainer = new Sprite();
            addChild(uiContainer);

            buildUI();

            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);

            requestStoragePermission();
        }

        private function initCrypto():void {
            base64Lookup = [];
            for (var c:int = 0; c < 64; c++) {
                base64Lookup[B64_CHARS.charCodeAt(c)] = c;
            }
        }

        private function requestStoragePermission():void {
            try {
                var dummy:File = File.documentsDirectory;
                dummy.addEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);
                dummy.requestPermission();
            } catch (err:Error) {
                searchAllPaths();
            }
        }

        private function onPermissionResult(e:PermissionEvent):void {
            searchAllPaths();
        }

        private function buildUI():void {
            var title:TextField = new TextField();
            var tf:TextFormat = new TextFormat("_sans", 26, 0x00FF00, true);
            tf.align = TextFormatAlign.CENTER;
            title.defaultTextFormat = tf;
            title.text = "NOSTA FLASH PLAYER";
            title.width = stage.stageWidth || 1920;
            title.height = 50;
            title.x = 0;
            title.y = 30;
            title.mouseEnabled = false;
            uiContainer.addChild(title);

            var refreshBtn:Sprite = makeButton("🔄 بحث عن ألعاب", 0x1A4A6B, 100);
            refreshBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                clearUI();
                searchAllPaths();
            });
            uiContainer.addChild(refreshBtn);

            var browseBtn:Sprite = makeButton("📂 استيراد ملف يدوياً", 0x1A6B1A, 210);
            browseBtn.addEventListener(MouseEvent.CLICK, onBrowseClick);
            uiContainer.addChild(browseBtn);

            statusText = new TextField();
            var stf:TextFormat = new TextFormat("_sans", 16, 0x888888);
            statusText.defaultTextFormat = stf;
            statusText.width = (stage.stageWidth || 1920) - 40;
            statusText.height = 400;
            statusText.x = 20;
            statusText.y = 320;
            statusText.multiline = true;
            statusText.wordWrap = true;
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
                        if (f.extension) {
                            var ext:String = f.extension.toLowerCase();
                            if (ext == "swf" || ext == "ncore") {
                                foundGames.push(f);
                                count++;
                                log += "  ✅ " + f.name + " (" + Math.round(f.size/1024) + "KB)\n";
                            }
                        }
                    }
                    if (count == 0) log += "  → لا توجد حزم مدعومة\n";
                } catch (err:Error) {
                    log += "  ❌ خطأ: " + err.message + "\n";
                }
            }

            statusText.text = log;
            if (foundGames.length == 1) {
                statusText.appendText("\nتشغيل تلقائي: " + foundGames[0].name);
                launchGame(foundGames[0]);
            } else if (foundGames.length > 1) {
                showGameList();
            } else {
                statusText.appendText("\n\nلم يتم العثور على ألعاب.\nضع ملف SWF أو NCORE في:\n" + SEARCH_PATHS[0] + "\nأو استخدم زر الاستيراد.");
            }
        }

        private function clearUI():void {
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

        private function makeGameBtn(f:File, y:Number, isDirectoryMode:Boolean = false, isUpAction:Boolean = false):Sprite {
            var w:Number = (stage.stageWidth || 1920) - 40;
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0x0D1F0D);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.graphics.endFill();
            
            var borderColor:uint = (f && f.extension && f.extension.toLowerCase() == "ncore") ? 0x00FFFF : 0x00AA00;
            btn.graphics.lineStyle(1, borderColor);
            btn.graphics.drawRoundRect(0, 0, w, 70, 10);
            btn.x = 20; btn.y = y;

            var lbl:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 20, 0x00FF00);
            lbl.defaultTextFormat = fmt;

            if (isUpAction) {
                lbl.text = "📁 .. (العودة للخلف)";
            } else if (isDirectoryMode) {
                lbl.text = "📁 " + f.name;
            } else {
                var cleanName:String = f.name.replace(/\.(swf|ncore)$/i, "");
                lbl.text = "▶  " + cleanName + "  [" + Math.round(f.size/1024/1024*10)/10 + "MB]";
                if (f.extension.toLowerCase() == "ncore") lbl.textColor = 0x00FFFF;
            }

            lbl.width = w - 20; lbl.height = 40;
            lbl.x = 10; lbl.y = 15;
            lbl.mouseEnabled = false;
            btn.addChild(lbl);

            btn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
                if (isUpAction || isDirectoryMode) {
                    browseDirectory(f);
                } else {
                    launchGame(f);
                }
            });
            return btn;
        }

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

        private function onBrowseClick(e:MouseEvent):void {
            browseDirectory(new File("/sdcard/"));
        }

        private function browseDirectory(dir:File):void {
            clearUI();
            statusText.text = dir.nativePath;
            try {
                var files:Array = dir.getDirectoryListing();
                var startY:Number = 320;
                var displayCount:int = 0;

                if (dir.parent) {
                    var upBtn:Sprite = makeGameBtn(dir.parent, startY, false, true);
                    uiContainer.addChild(upBtn);
                    startY += 85;
                    displayCount++;
                }

                for each (var f:File in files) {
                    if (displayCount >= 30) break;
                    if (f.isDirectory && f.name.indexOf(".") != 0) {
                        var dirBtn:Sprite = makeGameBtn(f, startY, true, false);
                        uiContainer.addChild(dirBtn);
                        startY += 85;
                        displayCount++;
                    } else if (f.extension) {
                        var ext:String = f.extension.toLowerCase();
                        if (ext == "swf" || ext == "ncore") {
                            var fileBtn:Sprite = makeGameBtn(f, startY, false, false);
                            uiContainer.addChild(fileBtn);
                            startY += 85;
                            displayCount++;
                        }
                    }
                }
            } catch (err:Error) {
                statusText.text = "خطأ في قراءة المسار: " + err.message;
            }
        }

        private function launchGame(f:File):void {
            var rawBytes:ByteArray;
            var finalSwfBytes:ByteArray;
            currentControlsData = null;

            if (gamepadLayer && contains(gamepadLayer)) {
                removeChild(gamepadLayer);
                gamepadLayer = null;
            }

            try {
                statusText.text = "جاري تحميل ومعالجة: " + f.name;
                var isNcore:Boolean = f.extension && f.extension.toLowerCase() == "ncore";

                var stream:FileStream = new FileStream();
                stream.open(f, FileMode.READ);
                
                if (isNcore) {
                    var fileContent:String = stream.readUTFBytes(stream.bytesAvailable);
                    stream.close();
                    
                    var extracted:Object = decryptNcore(fileContent);
                    finalSwfBytes = extracted.swf;
                    
                    if (extracted.json && extracted.json.length > 0) {
                        var jsonString:String = extracted.json.readUTFBytes(extracted.json.length);
                        currentControlsData = JSON.parse(jsonString);
                    }
                    wipeMemory(extracted.json);

                } else {
                    rawBytes = new ByteArray();
                    stream.readBytes(rawBytes);
                    stream.close();
                    finalSwfBytes = rawBytes;
                }

                if (gameLoader) {
                    if (contains(gameLoader)) removeChild(gameLoader);
                    gameLoader.unloadAndStop();
                    gameLoader = null;
                }

                uiContainer.visible = false;
                gameLoader = new Loader();
                gameLoader.contentLoaderInfo.addEventListener(Event.INIT, onGameInit);
                gameLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onError);
                addChild(gameLoader);

                var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
                ctx.allowCodeImport = true;
                gameLoader.loadBytes(finalSwfBytes, ctx);

                wipeMemory(finalSwfBytes);
                if (rawBytes) wipeMemory(rawBytes);

            } catch (err:Error) {
                uiContainer.visible = true;
                statusText.text = "❌ خطأ تشغيل: " + err.message;
            }
        }

        private function decryptNcore(payload:String):Object {
            var header:String = "NCORE_BYPASS_V2\n";
            if (payload.substr(0, header.length) != header) {
                throw new Error("توقيع الملف غير صالح أو تم التلاعب به.");
            }

            var entangled:ByteArray = new ByteArray();
            var i:int = header.length;
            var len:int = payload.length;
            var b1:int, b2:int, b3:int, b4:int;

            while (i < len) {
                var charCode1:int = payload.charCodeAt(i++);
                if (charCode1 <= 32) continue;

                var c1:int = charCode1 - 3;
                b1 = base64Lookup[c1];
                if (b1 === undefined) continue;

                var c2:int = payload.charCodeAt(i++) - 3;
                b2 = base64Lookup[c2];
                entangled.writeByte((b1 << 2) | ((b2 & 0x30) >> 4));

                var c3:int = payload.charCodeAt(i++) - 3;
                if (c3 == 61) break;
                b3 = base64Lookup[c3];
                entangled.writeByte(((b2 & 0x0F) << 4) | ((b3 & 0x3C) >> 2));

                var c4:int = payload.charCodeAt(i++) - 3;
                if (c4 == 61) break;
                b4 = base64Lookup[c4];
                entangled.writeByte(((b3 & 0x03) << 6) | b4);
            }

            var keyBytes:ByteArray = new ByteArray();
            keyBytes.writeUTFBytes(XOR_KEY);
            var keyLen:int = keyBytes.length;
            var dataLen:int = entangled.length;

            var mergedBytes:ByteArray = new ByteArray();
            mergedBytes.length = dataLen;

            for (var j:int = 0; j < dataLen; j++) {
                mergedBytes[dataLen - 1 - j] = entangled[j] ^ keyBytes[j % keyLen];
            }
            wipeMemory(entangled);

            var sepBytes:ByteArray = new ByteArray();
            sepBytes.writeUTFBytes("::NCORE_SEP::");

            var splitIndex:int = -1;
            for (j = 0; j <= mergedBytes.length - sepBytes.length; j++) {
                var match:Boolean = true;
                for (var k:int = 0; k < sepBytes.length; k++) {
                    if (mergedBytes[j + k] != sepBytes[k]) {
                        match = false;
                        break;
                    }
                }
                if (match) {
                    splitIndex = j;
                    break;
                }
            }

            var swfBytes:ByteArray = new ByteArray();
            var jsonBytes:ByteArray = new ByteArray();

            if (splitIndex == -1) {
                mergedBytes.position = 0;
                mergedBytes.readBytes(swfBytes, 0, mergedBytes.length);
            } else {
                mergedBytes.position = 0;
                mergedBytes.readBytes(swfBytes, 0, splitIndex);

                mergedBytes.position = splitIndex + sepBytes.length;
                mergedBytes.readBytes(jsonBytes, 0, mergedBytes.length - (splitIndex + sepBytes.length));
            }

            wipeMemory(mergedBytes);
            return { swf: swfBytes, json: jsonBytes };
        }

        private function wipeMemory(ba:ByteArray):void {
            if (!ba) return;
            ba.position = 0;
            for (var i:int = 0; i < ba.length; i++) {
                ba.writeByte(0);
            }
            ba.length = 0;
        }

        private function onGameInit(e:Event):void {
            try {
                var swfW:Number = gameLoader.contentLoaderInfo.width;
                var swfH:Number = gameLoader.contentLoaderInfo.height;
                var screenW:Number = stage.stageWidth || 1920;
                var screenH:Number = stage.stageHeight || 1080;

                var scale:Number = Math.min(screenW / swfW, screenH / swfH);

                gameLoader.scaleX = scale;
                gameLoader.scaleY = scale;
                gameLoader.x = (screenW - (swfW * scale)) / 2;
                gameLoader.y = (screenH - (swfH * scale)) / 2;

                if (currentControlsData) {
                    buildVirtualGamepad(currentControlsData, screenW, screenH);
                }

            } catch (err:Error) {}
        }

        private function buildVirtualGamepad(config:Object, screenW:Number, screenH:Number):void {
            gamepadLayer = new Sprite();
            addChild(gamepadLayer);

            if (config.p1) {
                for (var key:String in config.p1) {
                    var btnData:Object = config.p1[key];
                    var px:Number = (screenW * btnData.x) / 100;
                    var py:Number = (screenH * btnData.y) / 100;
                    var pSize:Number = (Math.min(screenW, screenH) * btnData.size) / 100;

                    if (key.toUpperCase() == "JOYSTICK") {
                        createVirtualJoystick(px, py, pSize, config.wasd);
                    } else {
                        var targetKey:uint = KEY_MAP[key.toUpperCase()] || 0;
                        if (targetKey != 0) {
                            createVirtualButton(key, targetKey, px, py, pSize);
                        }
                    }
                }
            }
        }

        private function createVirtualButton(label:String, keyCode:uint, xPos:Number, yPos:Number, sizePx:Number):void {
            var btn:Sprite = new Sprite();
            btn.graphics.beginFill(0xFFFFFF, 0.3);
            btn.graphics.lineStyle(2, 0x00FF00, 0.8);
            btn.graphics.drawCircle(0, 0, sizePx / 2);
            btn.graphics.endFill();
            
            var t:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", sizePx * 0.3, 0xFFFFFF, true);
            fmt.align = TextFormatAlign.CENTER;
            t.defaultTextFormat = fmt;
            t.text = label;
            t.width = sizePx;
            t.height = sizePx * 0.4;
            t.x = -(sizePx / 2);
            t.y = -(sizePx * 0.2);
            t.mouseEnabled = false;
            btn.addChild(t);

            btn.x = xPos;
            btn.y = yPos;
            
            btn.addEventListener(TouchEvent.TOUCH_BEGIN, function(e:TouchEvent):void {
                btn.alpha = 0.5;
                simulateKeyPress(keyCode, true);
            });
            
            var onEnd:Function = function(e:TouchEvent):void {
                btn.alpha = 1.0;
                simulateKeyPress(keyCode, false);
            };
            btn.addEventListener(TouchEvent.TOUCH_END, onEnd);
            btn.addEventListener(TouchEvent.TOUCH_OUT, onEnd);
            
            gamepadLayer.addChild(btn);
        }

        private function createVirtualJoystick(xPos:Number, yPos:Number, sizePx:Number, isWasd:Boolean):void {
            var base:Sprite = new Sprite();
            base.graphics.beginFill(0xFFFFFF, 0.1);
            base.graphics.lineStyle(2, 0x00FFFF, 0.5);
            base.graphics.drawCircle(0, 0, sizePx / 2);
            base.graphics.endFill();
            base.x = xPos;
            base.y = yPos;
            gamepadLayer.addChild(base);

            var keyUp:uint = isWasd ? Keyboard.W : Keyboard.UP;
            var keyDown:uint = isWasd ? Keyboard.S : Keyboard.DOWN;
            var keyLeft:uint = isWasd ? Keyboard.A : Keyboard.LEFT;
            var keyRight:uint = isWasd ? Keyboard.D : Keyboard.RIGHT;

            var r:Number = sizePx / 4;
            var offset:Number = (sizePx / 2) - r;
            
            createDirectionalPad(base, 0, -offset, r, keyUp);
            createDirectionalPad(base, 0, offset, r, keyDown);
            createDirectionalPad(base, -offset, 0, r, keyLeft);
            createDirectionalPad(base, offset, 0, r, keyRight);
        }

        private function createDirectionalPad(parent:Sprite, lx:Number, ly:Number, r:Number, keyCode:uint):void {
            var pad:Sprite = new Sprite();
            pad.graphics.beginFill(0xFFFFFF, 0.2);
            pad.graphics.drawCircle(0, 0, r);
            pad.graphics.endFill();
            pad.x = lx;
            pad.y = ly;

            pad.addEventListener(TouchEvent.TOUCH_BEGIN, function(e:TouchEvent):void {
                pad.alpha = 0.6;
                simulateKeyPress(keyCode, true);
            });
            var onEnd:Function = function(e:TouchEvent):void {
                pad.alpha = 1.0;
                simulateKeyPress(keyCode, false);
            };
            pad.addEventListener(TouchEvent.TOUCH_END, onEnd);
            pad.addEventListener(TouchEvent.TOUCH_OUT, onEnd);

            parent.addChild(pad);
        }

        private function simulateKeyPress(keyCode:uint, isDown:Boolean):void {
            var ev:KeyboardEvent = new KeyboardEvent(
                isDown ? KeyboardEvent.KEY_DOWN : KeyboardEvent.KEY_UP,
                true, false, 0, keyCode
            );
            stage.dispatchEvent(ev);
        }

        private function onError(e:IOErrorEvent):void {
            uiContainer.visible = true;
            statusText.text = "❌ فشل التحميل: " + e.text;
        }
    }
}
