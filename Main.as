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
    import flash.events.ServerSocketConnectEvent;
    import flash.net.URLRequest;
    import flash.net.ServerSocket;
    import flash.net.Socket;
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
        private var uiContainer:Sprite;
        private var listContainer:Sprite;
        private var currentDir:File;
        private var errorTextField:TextField;
        private var backTextField:TextField;
        private var exitButton:Sprite;
        private var awakenButton:Sprite;
        
        private var logFile:File;
        private var logLines:Array = [];
        
        private var isDragging:Boolean = false;
        private var startY:Number;
        private var listStartY:Number;
        private var moveThreshold:Number = 15;
        private var hasMoved:Boolean = false;
        private var totalListHeight:Number = 0;

        private var serverSocket:ServerSocket;
        private var activeSockets:Vector.<Socket> = new Vector.<Socket>();
        private var servingFile:File;
        private const SERVER_PORT:int = 8765;

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

            if (File.permissionStatus != PermissionStatus.GRANTED) {
                var permFile:File = new File("/storage/emulated/0");
                permFile.addEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);
                permFile.requestPermission();
            } else {
                onPermissionGranted();
            }
        }

        private function onPermissionResult(e:PermissionEvent):void {
            (e.target as File).removeEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);
            onPermissionGranted();
        }

        private function onPermissionGranted():void {
            try {
                var logDir:File = new File("/storage/emulated/0/nostagames");
                if (!logDir.exists) logDir.createDirectory();
                logFile = logDir.resolvePath("nostagames_log.txt");
            } catch (e:Error) {
                logFile = File.applicationStorageDirectory.resolvePath("nostagames_log.txt");
            }

            log("=== Nostagames V5 (Server + Awaken) Started ===");

            startLocalServer();
            setupExitButton();
            setupAwakenButton();
            setupFileManager();
        }

        private function log(msg:String):void {
            var now:Date = new Date();
            logLines.push("[" + now.toTimeString().substr(0, 8) + "] " + msg);
            flushLog();
        }

        private function flushLog():void {
            if (!logFile) return;
            try {
                var s:FileStream = new FileStream();
                s.open(logFile, FileMode.WRITE);
                s.writeUTFBytes(logLines.join("\n") + "\n");
                s.close();
            } catch (e:Error) {}
        }

        private function startLocalServer():void {
            if (ServerSocket.isSupported) {
                try {
                    serverSocket = new ServerSocket();
                    serverSocket.bind(SERVER_PORT, "127.0.0.1");
                    serverSocket.addEventListener(ServerSocketConnectEvent.CONNECT, onClientConnect);
                    serverSocket.listen();
                    log("Server listening on port " + SERVER_PORT);
                } catch (e:Error) {
                    log("Server failed to bind: " + e.message);
                }
            }
        }

        private function onClientConnect(e:ServerSocketConnectEvent):void {
            var client:Socket = e.socket;
            activeSockets.push(client);
            client.addEventListener(ProgressEvent.SOCKET_DATA, onClientData);
            client.addEventListener(Event.CLOSE, onClientClose);
            client.addEventListener(IOErrorEvent.IO_ERROR, onClientError);
        }

        private function onClientData(e:ProgressEvent):void {
            var client:Socket = e.target as Socket;
            try {
                var requestStr:String = client.readUTFBytes(client.bytesAvailable);
                var lines:Array = requestStr.split("\n");
                var firstLine:String = lines[0];
                
                log("Req: " + firstLine);

                var pathMatch:Array = firstLine.match(/GET\s+\/([^\s\?]*)/);
                if (!pathMatch) return;
                
                var reqPath:String = decodeURIComponent(pathMatch[1]);
                if (reqPath == "" && servingFile) reqPath = servingFile.name;

                if (reqPath == "crossdomain.xml") {
                    var crossdomain:String = '<?xml version="1.0"?><cross-domain-policy><allow-access-from domain="*" /></cross-domain-policy>';
                    var cHeader:String = "HTTP/1.1 200 OK\r\n" +
                                         "Content-Type: text/xml\r\n" +
                                         "Content-Length: " + crossdomain.length + "\r\n" +
                                         "Connection: close\r\n\r\n";
                    client.writeUTFBytes(cHeader);
                    client.writeUTFBytes(crossdomain);
                    client.flush();
                    return;
                }

                var targetFile:File = null;
                if (servingFile && (reqPath == servingFile.name || reqPath == encodeURIComponent(servingFile.name))) {
                    targetFile = servingFile;
                } else if (servingFile && servingFile.parent) {
                    try {
                        targetFile = servingFile.parent.resolvePath(reqPath);
                    } catch(err:Error) {
                        targetFile = null;
                    }
                }

                if (targetFile && targetFile.exists && !targetFile.isDirectory) {
                    var fs:FileStream = new FileStream();
                    fs.open(targetFile, FileMode.READ);
                    var bytes:ByteArray = new ByteArray();
                    fs.readBytes(bytes);
                    fs.close();

                    var ext:String = targetFile.extension ? targetFile.extension.toLowerCase() : "";
                    var contentType:String = "application/octet-stream";
                    if (ext == "swf") contentType = "application/x-shockwave-flash";
                    else if (ext == "xml") contentType = "text/xml";
                    else if (ext == "png") contentType = "image/png";
                    else if (ext == "jpg" || ext == "jpeg") contentType = "image/jpeg";
                    else if (ext == "json") contentType = "application/json";
                    else if (ext == "txt") contentType = "text/plain";

                    var header:String = "HTTP/1.1 200 OK\r\n" +
                                        "Content-Type: " + contentType + "\r\n" +
                                        "Content-Length: " + bytes.length + "\r\n" +
                                        "Access-Control-Allow-Origin: *\r\n" +
                                        "Connection: close\r\n\r\n";

                    client.writeUTFBytes(header);
                    client.writeBytes(bytes);
                    client.flush();
                } else {
                    log("404 Not Found: " + reqPath);
                    var notFound:String = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
                    client.writeUTFBytes(notFound);
                    client.flush();
                    try { client.close(); } catch(e:Error) {}
                }
            } catch (err:Error) {
                log("Socket Error: " + err.message);
            }
        }

        private function onClientClose(e:Event):void {
            removeSocket(e.target as Socket);
        }

        private function onClientError(e:IOErrorEvent):void {
            removeSocket(e.target as Socket);
        }

        private function removeSocket(client:Socket):void {
            if (!client) return;
            client.removeEventListener(ProgressEvent.SOCKET_DATA, onClientData);
            client.removeEventListener(Event.CLOSE, onClientClose);
            client.removeEventListener(IOErrorEvent.IO_ERROR, onClientError);
            var index:int = activeSockets.indexOf(client);
            if (index != -1) {
                activeSockets.splice(index, 1);
            }
        }

        private function setupExitButton():void {
            if (exitButton) {
                exitButton.removeEventListener(MouseEvent.CLICK, onExitClick);
                if (contains(exitButton)) removeChild(exitButton);
            }

            exitButton = new Sprite();
            exitButton.graphics.beginFill(0xDD0000, 1.0);
            exitButton.graphics.drawRoundRect(0, 0, 80, 80, 14);
            exitButton.graphics.endFill();

            var tf:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 50, 0xFFFFFF, true);
            fmt.align = "center";
            tf.defaultTextFormat = fmt;
            tf.text = "X";
            tf.width = 80;
            tf.height = 70;
            tf.x = 0;
            tf.y = 8;
            tf.selectable = false;
            tf.mouseEnabled = false;
            exitButton.addChild(tf);
            
            exitButton.x = stage.stageWidth > 0 ? stage.stageWidth - 90 : 1190;
            exitButton.y = 10;
            exitButton.mouseChildren = false;
            exitButton.mouseEnabled = true;
            exitButton.addEventListener(MouseEvent.CLICK, onExitClick);

            addChild(exitButton);
        }

        private function setupAwakenButton():void {
            if (awakenButton) {
                awakenButton.removeEventListener(MouseEvent.CLICK, onAwakenClick);
                if (contains(awakenButton)) removeChild(awakenButton);
            }

            awakenButton = new Sprite();
            awakenButton.graphics.beginFill(0x00CC00, 1.0);
            awakenButton.graphics.drawRoundRect(0, 0, 220, 80, 14);
            awakenButton.graphics.endFill();

            var tf:TextField = new TextField();
            var fmt:TextFormat = new TextFormat("_sans", 38, 0xFFFFFF, true);
            fmt.align = "center";
            tf.defaultTextFormat = fmt;
            tf.text = "AWAKEN";
            tf.width = 220;
            tf.height = 70;
            tf.x = 0;
            tf.y = 15;
            tf.selectable = false;
            tf.mouseEnabled = false;
            awakenButton.addChild(tf);

            awakenButton.x = 20;
            awakenButton.y = 10;
            awakenButton.mouseChildren = false;
            awakenButton.mouseEnabled = true;
            awakenButton.visible = false;
            awakenButton.addEventListener(MouseEvent.CLICK, onAwakenClick);

            addChild(awakenButton);
        }

        private function onAwakenClick(e:MouseEvent):void {
            if (swfLoader && swfLoader.content) {
                log("Executing Awakening Injection...");
                var mc:* = swfLoader.content;
                try {
                    mc.dispatchEvent(new Event(Event.COMPLETE, true, false));
                    mc.dispatchEvent(new Event("loadComplete", true, false));
                    mc.dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, false, false, 1000, 1000));
                    
                    var funcs:Array = ["init", "start", "startGame", "playGame", "completeLoad", "onLoadComplete", "main", "checkLoad"];
                    for each (var fName:String in funcs) {
                        if (mc.hasOwnProperty(fName) && typeof mc[fName] == "function") {
                            mc[fName]();
                            log("Injected call to: " + fName);
                        }
                    }
                    
                    mc.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, stage.stageWidth/2, stage.stageHeight/2));
                    
                    if (mc.hasOwnProperty("play")) {
                        mc.play();
                    }
                    
                    awakenButton.visible = false;
                } catch(err:Error) {
                    log("Awaken Failed: " + err.message);
                }
            }
        }

        private function bringUIFront():void {
            if (exitButton && contains(exitButton)) {
                setChildIndex(exitButton, numChildren - 1);
            }
            if (awakenButton && contains(awakenButton)) {
                setChildIndex(awakenButton, numChildren - 1);
            }
        }

        private function onExitClick(e:MouseEvent):void {
            flushLog();
            NativeApplication.nativeApplication.exit(0);
        }

        private function setupFileManager():void {
            uiContainer = new Sprite();
            addChild(uiContainer);
            bringUIFront();

            listContainer = new Sprite();
            uiContainer.addChild(listContainer);

            stage.addEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.addEventListener(MouseEvent.MOUSE_UP, onUp);

            currentDir = new File("/storage/emulated/0");
            if (!currentDir.exists) currentDir = File.documentsDirectory;

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
            item.graphics.drawRect(0, 0, stage.stageWidth > 0 ? stage.stageWidth : 1280, 75);
            item.graphics.endFill();

            var tf:TextField = new TextField();
            tf.defaultTextFormat = format;
            tf.textColor = color;
            tf.text = txt;
            tf.width = (stage.stageWidth > 0 ? stage.stageWidth : 1280) - 40;
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
                    loadGame(f);
                }
            }
        }

        private function loadGame(file:File):void {
            if (uiContainer && contains(uiContainer)) removeChild(uiContainer);
            stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMove);
            stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);

            cleanupErrorUI();
            cleanupLoaders();
            
            servingFile = file;
            awakenButton.visible = false;
            
            var safeName:String = encodeURIComponent(file.name);
            var url:String = "http://127.0.0.1:" + SERVER_PORT + "/" + safeName;

            log("Loading from server: " + url);

            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.allowCodeImport = true;

            swfLoader = new Loader();
            swfLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onGameLoaded);
            swfLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onGameError);
            swfLoader.load(new URLRequest(url), context);
            
            addChild(swfLoader);
            bringUIFront();
        }

        private function onGameLoaded(e:Event):void {
            var info:LoaderInfo = e.target as LoaderInfo;
            log("Game loaded successfully. URL: " + info.url);
            
            var fps:Number = info.frameRate;
            if (fps > 0 && fps <= 60) {
                stage.frameRate = fps;
            }

            var gameW:Number = info.width > 0 ? info.width : 550;
            var gameH:Number = info.height > 0 ? info.height : 400;
            var screenW:Number = stage.stageWidth > 0 ? stage.stageWidth : 1280;
            var screenH:Number = stage.stageHeight > 0 ? stage.stageHeight : 720;

            var scale:Number = screenH / gameH;
            if (gameW * scale > screenW) scale = screenW / gameW;

            swfLoader.scaleX = scale;
            swfLoader.scaleY = scale;
            swfLoader.x = Math.round((screenW - gameW * scale) / 2);
            swfLoader.y = Math.round((screenH - gameH * scale) / 2);

            awakenButton.visible = true;
            bringUIFront();
            flushLog();
        }

        private function onGameError(e:IOErrorEvent):void {
            log("Loader IO Error: " + e.text);
            cleanupLoaders();
            cleanupErrorUI();
            stage.frameRate = 60;

            var format:TextFormat = new TextFormat("_sans", 34, 0xFF4444, true);
            errorTextField = new TextField();
            errorTextField.defaultTextFormat = format;
            errorTextField.multiline = true;
            errorTextField.wordWrap = true;
            errorTextField.text = "Error\n" + e.text;
            errorTextField.width = (stage.stageWidth > 0 ? stage.stageWidth : 1280) - 80;
            errorTextField.height = 200;
            errorTextField.x = 40;
            errorTextField.y = ((stage.stageHeight > 0 ? stage.stageHeight : 720) / 2) - 150;
            errorTextField.selectable = false;
            addChild(errorTextField);

            var backFormat:TextFormat = new TextFormat("_sans", 40, 0xFFFF00, true);
            backTextField = new TextField();
            backTextField.defaultTextFormat = backFormat;
            backTextField.text = "[ BACK ]";
            backTextField.width = (stage.stageWidth > 0 ? stage.stageWidth : 1280) - 80;
            backTextField.height = 70;
            backTextField.x = 40;
            backTextField.y = ((stage.stageHeight > 0 ? stage.stageHeight : 720) / 2) + 80;
            backTextField.selectable = false;
            backTextField.mouseEnabled = true;
            backTextField.addEventListener(MouseEvent.CLICK, onBackToMenu);
            addChild(backTextField);

            bringUIFront();
        }

        private function onBackToMenu(e:MouseEvent):void {
            servingFile = null;
            cleanupLoaders();
            cleanupErrorUI();
            awakenButton.visible = false;
            stage.frameRate = 60;
            while (numChildren > 0) removeChildAt(0);
            setupExitButton();
            setupAwakenButton();
            setupFileManager();
        }

        private function cleanupLoaders():void {
            if (swfLoader) {
                swfLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, onGameLoaded);
                swfLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, onGameError);
                swfLoader.unloadAndStop(true);
                if (contains(swfLoader)) removeChild(swfLoader);
                swfLoader = null;
            }
            
            for (var i:int = activeSockets.length - 1; i >= 0; i--) {
                var client:Socket = activeSockets[i];
                try {
                    client.close();
                } catch (e:Error) {}
            }
            activeSockets.length = 0;
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
