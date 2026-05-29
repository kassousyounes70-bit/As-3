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
            graphics.drawRect(0, 0, 2000, 2000);
            graphics.endFill();

            statusText = new TextField();
            statusText.defaultTextFormat = new TextFormat("_sans", 32, 0xFFFFFF);
            statusText.width = 900;
            statusText.height = 200;
            statusText.x = 50;
            statusText.y = 250;
            addChild(statusText);

            browseButton = new Sprite();
            browseButton.graphics.beginFill(0x007ACC);
            browseButton.graphics.drawRect(0, 0, 400, 120);
            browseButton.graphics.endFill();
            browseButton.x = 50;
            browseButton.y = 80;
            addChild(browseButton);

            browseButton.addEventListener(MouseEvent.CLICK, onBrowseClick);
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, onInvoke);
        }

        private function onInvoke(e:InvokeEvent):void {
            if (e.arguments && e.arguments.length > 0) {
                var filePath:String = e.arguments[0] as String;
                if (filePath) {
                    var sharedFile:File = new File(filePath);
                    if (sharedFile.exists) {
                        injectPayload(sharedFile);
                    }
                }
            }
        }

        private function onBrowseClick(e:MouseEvent):void {
            fileToLoad = new File();
            fileToLoad.addEventListener(Event.SELECT, onFileSelected);
            fileToLoad.browseForOpen("Select Game");
        }

        private function onFileSelected(e:Event):void {
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
                statusText.text = "";
                browseButton.visible = false;
            } catch (error:Error) {
                statusText.text = error.message;
            }
        }
    }
}
