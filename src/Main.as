package {
    import flash.desktop.NativeApplication;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.InvokeEvent;
    import flash.events.MouseEvent;
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
        private var browseButton:Sprite;
        private var statusText:TextField;
        private var fileToLoad:File;
        private var gameLoader:Loader;

        public function Main() {
            stage.align = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            
            graphics.beginFill(0x1A1A1A);
            graphics.drawRect(0, 0, 2500, 2500);
            graphics.endFill();

            statusText = new TextField();
            var textFormat:TextFormat = new TextFormat("_sans", 24, 0x00FF00);
            statusText.defaultTextFormat = textFormat;
            statusText.width = stage.stageWidth - 40;
            statusText.height = stage.stageHeight - 200;
            statusText.x = 20;
            statusText.y = 180;
            statusText.multiline = true;
            statusText.wordWrap = true;
            statusText.text = "System Ready. Waiting for file...";
            addChild(statusText);

            browseButton = new Sprite();
            browseButton.graphics.beginFill(0x007ACC);
            browseButton.graphics.drawRect(0, 0, 300, 80);
            browseButton.graphics.endFill();
            browseButton.x = (stage.stageWidth - 300) / 2;
            browseButton.y = 50;
            
            var btnText:TextField = new TextField();
            var btnFormat:TextFormat = new TextFormat("_sans", 28, 0xFFFFFF, true);
            btnFormat.align = TextFormatAlign.CENTER;
            btnText.defaultTextFormat = btnFormat;
            btnText.text = "Select SWF File";
            btnText.width = 300;
            btnText.height = 40;
            btnText.y = 20;
            btnText.mouseEnabled = false;
            browseButton.addChild(btnText);
            
            addChild(browseButton);

            browseButton.addEventListener(MouseEvent.CLICK, onBrowseClick);
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);
        }

        private function onInvoke(e:InvokeEvent):void {
            statusText.text = "Invoke triggered. Args length: " + e.arguments.length + "\n";
            if (e.arguments && e.arguments.length > 0) {
                var filePath:String = e.arguments[0] as String;
                statusText.appendText("Received path: " + filePath + "\n");
                
                try {
                    var sharedFile:File = new File(filePath);
                    if (sharedFile.exists) {
                        statusText.appendText("File exists. Attempting injection...\n");
                        injectPayload(sharedFile);
                    } else {
                        statusText.appendText("Error: File does not exist at path.\n");
                    }
                } catch (error:Error) {
                    statusText.appendText("Path parsing error: " + error.message + "\n");
                }
            }
        }

        private function onBrowseClick(e:MouseEvent):void {
            fileToLoad = new File();
            fileToLoad.addEventListener(Event.SELECT, onFileSelected);
            fileToLoad.browseForOpen("Select Game");
        }

        private function onFileSelected(e:Event):void {
            statusText.text = "Selected manually: " + fileToLoad.nativePath + "\n";
            injectPayload(fileToLoad);
        }

        private function injectPayload(targetFile:File):void {
            try {
                var stream:FileStream = new FileStream();
                stream.open(targetFile, FileMode.READ);
                var fileData:ByteArray = new ByteArray();
                stream.readBytes(fileData);
                stream.close();

                if (gameLoader != null) {
                    removeChild(gameLoader);
                    gameLoader.unloadAndStop();
                }

                gameLoader = new Loader();
                addChild(gameLoader);

                var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
                context.allowCodeImport = true;
                
                gameLoader.loadBytes(fileData, context);
                
                browseButton.visible = false;
                statusText.visible = false;
            } catch (error:Error) {
                statusText.appendText("Injection Error: " + error.message + "\n");
            }
        }
    }
}
