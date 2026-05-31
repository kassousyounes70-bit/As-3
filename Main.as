package {
    import flash.display.Sprite;
    import flash.display.Loader;
    import flash.display.StageScaleMode;
    import flash.display.StageAlign;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.PermissionEvent;
    import flash.net.URLRequest;
    import flash.net.FileFilter;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.filesystem.File;
    import flash.permissions.PermissionStatus;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;

    [SWF(width="1280", height="720", frameRate="60", backgroundColor="#000000")]
    public class Main extends Sprite {
        private var swfLoader:Loader;
        private var uiText:TextField;
        private var fileToOpen:File;

        public function Main() {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;

            setupUI();
            requestStoragePermissions();
        }

        private function setupUI():void {
            uiText = new TextField();
            var format:TextFormat = new TextFormat("_sans", 36, 0x00FF00, true);
            format.align = TextFormatAlign.CENTER;
            uiText.defaultTextFormat = format;
            uiText.text = "جاري التحقق من الصلاحيات...";
            uiText.width = 1000;
            uiText.height = 100;
            uiText.x = (stage.stageWidth - 1000) / 2;
            uiText.y = (stage.stageHeight - 100) / 2;
            uiText.selectable = false;
            addChild(uiText);

            stage.addEventListener(MouseEvent.CLICK, onStageClick);
        }

        private function requestStoragePermissions():void {
            if (File.permissionStatus != PermissionStatus.GRANTED) {
                var tempFile:File = File.documentsDirectory;
                tempFile.addEventListener(PermissionEvent.PERMISSION_STATUS, onPermissionResult);
                try {
                    tempFile.requestPermission();
                } catch (e:Error) {
                    uiText.text = "خطأ في طلب الصلاحية: " + e.message;
                }
            } else {
                uiText.text = "الصلاحيات جاهزة. اضغط هنا لاختيار ملف اللعبة (.swf)";
            }
        }

        private function onPermissionResult(event:PermissionEvent):void {
            if (event.status == PermissionStatus.GRANTED) {
                uiText.text = "تم منح الصلاحيات بنجاح. اضغط هنا لاختيار اللعبة.";
            } else {
                uiText.text = "تم رفض الصلاحيات. لا يمكن تشغيل الألعاب.";
            }
        }

        private function onStageClick(e:MouseEvent):void {
            if (File.permissionStatus == PermissionStatus.GRANTED) {
                openFilePicker();
            } else {
                requestStoragePermissions();
            }
        }

        private function openFilePicker():void {
            fileToOpen = new File();
            var swfFilter:FileFilter = new FileFilter("Flash Games (*.swf)", "*.swf");
            fileToOpen.addEventListener(Event.SELECT, onFileSelected);
            fileToOpen.browseForOpen("اختر لعبة الفلاش", [swfFilter]);
        }

        private function onFileSelected(event:Event):void {
            if (uiText && contains(uiText)) {
                removeChild(uiText);
            }
            loadGame(fileToOpen.url);
        }

        private function loadGame(path:String):void {
            if (swfLoader) {
                removeChild(swfLoader);
                swfLoader.unloadAndStop();
            }
            swfLoader = new Loader();
            
            var context:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
            context.allowCodeImport = true;
            
            swfLoader.load(new URLRequest(path), context);
            addChild(swfLoader);
        }
    }
}
