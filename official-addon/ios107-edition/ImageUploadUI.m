#import "ImageUploadUI.h"
#if TIO_IMAGE_RX_LAB
#import "ImageUploadTransport.h"
#import "ProtocolContext.h"
static TIOImageUpload *LabClient;
static TIOImageUploadTransport *LabCarrier;
BOOL TIOImageUploadLabConsumeFileEvent(NSDictionary *event){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"device"] isKindOfClass:NSDictionary.class]||
    ![TIOProtocolDevice() isEqual:event[@"device"][@"id"]])return NO;
 return [LabCarrier observeFileEvent:event client:LabClient];
}
#endif
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
// Downsample during decode on the phone; do not expand a full-resolution photo.
// Profile is shared by the phone encoder and AP parser; no large-PNG decoder.
static NSData *Luminance(NSURL *url){
 if(!url.isFileURL)return nil;
 NSDictionary *attr=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
 if(![attr[NSFileType] isEqual:NSFileTypeRegular]||[attr[NSFileSize] unsignedLongLongValue]>20*1024*1024)return nil;
 CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
 if(!source)return nil;
 CFStringRef type=CGImageSourceGetType(source);
 NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
 uint64_t w=[props[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue],h=[props[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
 BOOL valid=type&&(CFEqual(type,CFSTR("public.png"))||CFEqual(type,CFSTR("public.jpeg")))&&CGImageSourceGetCount(source)==1&&w&&h&&w<=16000000&&h<=16000000&&w<=16000000/h;
 if(!valid){CFRelease(source);return nil;}
 CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(TIO_W),(__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES});
 CFRelease(source);if(!thumb)return nil;
 NSMutableData *gray=[NSMutableData dataWithLength:TIO_PIXELS];CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
 CGContextRef ctx=CGBitmapContextCreate(gray.mutableBytes,TIO_W,TIO_H,8,TIO_W,space,(CGBitmapInfo)kCGImageAlphaNone);CGColorSpaceRelease(space);
 if(!ctx){CGImageRelease(thumb);return nil;}
 double sw=CGImageGetWidth(thumb),sh=CGImageGetHeight(thumb),s=fmin(TIO_W/sw,TIO_H/sh);
 CGContextSetGrayFillColor(ctx,0,1);CGContextFillRect(ctx,CGRectMake(0,0,TIO_W,TIO_H));CGContextSetInterpolationQuality(ctx,kCGInterpolationHigh);
 CGContextDrawImage(ctx,CGRectMake((TIO_W-sw*s)/2,(TIO_H-sh*s)/2,sw*s,sh*s),thumb);
 CGContextRelease(ctx);CGImageRelease(thumb);return gray;
}
@interface TIOImageUploadPage : UITableViewController<PHPickerViewControllerDelegate,UIDocumentPickerDelegate>
@property(nonatomic,strong) TIOImageUpload *client;
@property(nonatomic,strong) NSData *pixels;
@property(nonatomic,strong) UIImage *preview;
@property(nonatomic,copy) NSString *note;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation TIOImageUploadPage
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"图片传输 · 实验";self.note=@"仅本机选图与预览；原厂固件和当前 R3 头像固件不支持接收。需要新的 AP 模块和已验证路由。";
 self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=80;
 __weak typeof(self) weak=self;self.client.changed=^{[weak.tableView reloadData];};
 self.timer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){[weak.client tick:NSProcessInfo.processInfo.systemUptime];}];
}
#if TIO_IMAGE_RX_LAB
- (void)armManualSession{
 if(!self.pixels){self.note=@"先在手机选图，再在眼镜打开 Turbo Image RX；这样不会浪费眼镜 120 秒的窗口。";[self.tableView reloadData];return;}
 if(LabClient.task.length){self.note=@"本实验每次 App 启动仅提交一张。已有任务不自动重发；先确认结束并退出眼镜页面，再重启 App 做下一轮。";[self.tableView reloadData];return;}
 NSString *device=TIOProtocolDevice();
 if(!device.length){self.note=@"没有当前官方协议对象。请先在官方设备页确认连接；不会创建第二个蓝牙连接。";[self.tableView reloadData];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"N8 图片接收 · 人工会话" message:@"仅用于新 N8 / N8W 测试固件。必须亲眼看到眼镜 Turbo Image RX 页上的 SID；原厂/R3 不支持。输入当前 SID 后 30 秒内点发送。本轮最多一张，SDK 收到文件不代表镜片显示，需人工验收。不会触发 OTA。" preferredStyle:UIAlertControllerStyleAlert];
 [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"眼镜显示的十进制 SID";f.keyboardType=UIKeyboardTypeNumberPad;}];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 __weak typeof(self) weak=self;
 [a addAction:[UIAlertAction actionWithTitle:@"已看到 SID，开启本轮" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
  if(!weak)return;
  NSString *text=a.textFields.firstObject.text;NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
  unsigned long long sid=text.longLongValue;
  if(!text.length||text.length>10||[text rangeOfCharacterFromSet:bad].location!=NSNotFound||!sid||sid>UINT32_MAX||![device isEqual:TIOProtocolDevice()]){weak.note=@"SID 无效或设备已改变，未开启。";[weak.tableView reloadData];return;}
  NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ImageRXLab"] isDirectory:YES];
  LabCarrier=TIOImageUploadOfficialTransport(root,device);
  TIOImageUploadTransport *carrier=LabCarrier;
  LabClient=[[TIOImageUpload alloc]initWithSender:^(NSData *packet,NSString *target,NSString *task,void(^submitted)(BOOL)){
   [carrier sendPacket:packet device:target task:task submitted:submitted];
  }];
  if(![LabClient authorizeDevice:device session:(uint32_t)sid at:NSProcessInfo.processInfo.systemUptime])return;
  weak.client=LabClient;LabClient.changed=^{[weak.tableView reloadData];};
  weak.note=@"人工 SID 实验已开启，请在 30 秒内点发送。接收是否成功看镜片图片及 #1，自动显示 ACK 尚未接入。";[weak.tableView reloadData];
 }]];[self presentViewController:a animated:YES completion:nil];
}
#endif
- (void)dealloc{[_timer invalidate];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 6;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
 c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;
 NSArray *titles=@[@"1 · 从照片选择",@"或从文件选择 PNG / JPEG",[NSString stringWithFormat:@"2 · 传输预览（%d×%d）",TIO_W,TIO_H],@"3 · 发送到眼镜",@"接收与显示状态",@"原图解码是另一项测试"];
 c.textLabel.text=titles[p.row];
 if(p.row==2){c.imageView.image=self.preview;c.detailTextLabel.text=self.pixels?[NSString stringWithFormat:@"%d KiB 灰度像素；等比缩小留黑边。协议 v%d，需匹配本轮 AP。",TIO_PIXELS/1024,TIO_VERSION]:@"尚未选图";}
 if(p.row==3){BOOL ready=[self.client.state isEqual:@"ready"]||[self.client.state isEqual:@"render_submitted"];c.textLabel.textColor=(ready&&self.pixels&&!self.loading)?UIColor.systemBlueColor:UIColor.secondaryLabelColor;c.detailTextLabel.text=ready?@"仅发送当前图片，不启动 OTA，不上传云端":@"等待已验证的 AP 图片接收会话；当前不会盲发";}
 if(p.row==4){NSString *state=self.client.state?:@"receiver_not_verified";NSString *detail=self.note?:@"";
  if([state isEqual:@"submission_failed"])detail=@"手机提交失败，未确认眼镜收到；诊断已保存。请勿重复点发送。";
  else if([state isEqual:@"file_failed"])detail=@"官方文件通道返回失败，未确认显示。请勿重复发送。";
  else if([state isEqual:@"timeout_result_unknown"])detail=@"等待回执超时，结果未知；查看镜片 #1 和图片，不自动重发。";
  else if([state isEqual:@"file_received_waiting_renderer"])detail=@"文件成功回执已收到；没有自动显示 ACK，请检查镜片图片和 #1。";
  c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",state,detail];}
 if(p.row==5)c.detailTextLabel.text=@"256–1024 PNG 阶梯样本已在 Mac 准备；此页不会把手机缩图冒充眼镜大图能力。";
 return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(self.loading)return;
 if(p.row==0){PHPickerConfiguration *config=[[PHPickerConfiguration alloc]init];config.selectionLimit=1;config.filter=PHPickerFilter.imagesFilter;PHPickerViewController *picker=[[PHPickerViewController alloc]initWithConfiguration:config];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];}
 if(p.row==1){UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypePNG,UTTypeJPEG] asCopy:YES];picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];}
 if(p.row==3&&self.pixels){BOOL ok=[self.client sendLuminance:self.pixels at:NSProcessInfo.processInfo.systemUptime];self.note=ok?@"已提交本图，等待文件与 AP 独立回执；没有回执不会显示成功":@"未发送：未验证接收模块、会话不可用或已有任务。";[t reloadData];}
}
- (void)accept:(NSURL *)url generation:(NSUInteger)generation{
 // Called on the provider/background queue while the temporary URL is valid.
 BOOL scoped=[url startAccessingSecurityScopedResource];NSData *pixels=Luminance(url);if(scoped)[url stopAccessingSecurityScopedResource];
 dispatch_async(dispatch_get_main_queue(),^{
  if(generation!=self.generation)return;self.loading=NO;self.pixels=pixels;self.preview=nil;
  if(pixels){CGColorSpaceRef color=CGColorSpaceCreateDeviceGray();CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
   CGImageRef im=CGImageCreate(TIO_W,TIO_H,8,8,TIO_W,color,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
   if(im){self.preview=[UIImage imageWithCGImage:im];CGImageRelease(im);}CGDataProviderRelease(provider);CGColorSpaceRelease(color);
  }
  self.note=pixels?@"已在手机生成像素，无云上传；等待接收模块验收。":@"选图失败：只支持单帧 PNG/JPEG，最多 16MP、20 MiB。";
  [self.tableView reloadData];
 });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results{
 [picker dismissViewControllerAnimated:YES completion:nil];if(!results.count)return;
 self.loading=YES;NSUInteger generation=++self.generation;self.pixels=nil;self.preview=nil;[self.tableView reloadData];
 NSItemProvider *provider=results.firstObject.itemProvider;
 [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url,NSError *error){[self accept:url generation:generation];}];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 if(!urls.count)return;self.loading=YES;NSUInteger generation=++self.generation;self.pixels=nil;self.preview=nil;[self.tableView reloadData];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[self accept:urls.firstObject generation:generation];});
}
@end
UIViewController *TIOImageUploadController(TIOImageUpload *client){TIOImageUploadPage *p=[[TIOImageUploadPage alloc]initWithStyle:UITableViewStyleInsetGrouped];p.client=client;return p;}
#if TIO_IMAGE_RX_LAB
UIViewController *TIOImageUploadLabController(void){
 TIOImageUploadPage *p=(id)TIOImageUploadController(LabClient);[p loadViewIfNeeded];
 p.note=@"R4 单张传图验收：先选图，再打开眼镜 Turbo Image RX，点右上角输入 SID。原厂/R3 不支持；没有自动显示 ACK，最终看镜片 #1 和图片。";
#if TIO_IMAGE_RX_WIDE
 p.title=@"N8W · 传图 FIX 01";
 p.note=@"N8W 大区域版：眼镜页面540×180，图片512×128、64KiB。先选图，再滚动到眼镜第八项 Turbo Image RX，按下进入后输入 SID。仅匹配 N8W 协议v2；最终看镜片 #1 和图片。";
#endif
 p.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"输入 SID" style:UIBarButtonItemStylePlain target:p action:@selector(armManualSession)];return p;
}
#endif
