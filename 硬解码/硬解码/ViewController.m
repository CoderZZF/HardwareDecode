//
//  ViewController.m
//  硬解码
//
//  Created by zhangzhifu on 2017/3/13.
//  Copyright © 2017年 seemygo. All rights reserved.
//

#import "ViewController.h"
#import <VideoToolbox/VideoToolbox.h>

const char pStartCode[] = "\x00\x00\x00\x01";

@interface ViewController ()
{
    // 读取到的数据
    long inputMaxSize;
    long inputSize;
    uint8_t *inputBuffer;
    
    // 解析的数据
    long packetSize;
    uint8_t *packetBuffer;
    
    long spsSize;
    uint8_t *pSPS;
    
    long ppsSize;
    uint8_t *pPPS;
}
@property (nonatomic, weak) CADisplayLink *displayLink;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 1. 创建CADisplayLink
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink = displayLink;
    self.displayLink.frameInterval = 2;
    [self.displayLink setPaused:YES];
    
    // 2. 创建NSInputStream
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"123.h264" ofType:nil];
    self.inputStream = [NSInputStream inputStreamWithFileAtPath:filePath];
    
    // 3. 创建队列
    self.queue = dispatch_get_global_queue(0, 0);
}


- (IBAction)play:(id)sender {
    // 1. 初始化一次读取多少数据,以及数据的长度,数据存放在哪里
    inputMaxSize = 720 * 1280;
    inputSize = 0;
    inputBuffer = malloc(inputMaxSize);
    
    // 2. 打开inputStream
    [self.inputStream open];
    
    // 开启定时器
    [self.displayLink setPaused:NO];
}


// 开始读取数据
- (void)updateFrame {
    dispatch_sync(_queue, ^{
        // 1. 读取数据
        [self readPacket];
        
        // 2. 判断数据的类型
        if (packetSize == 0 && packetBuffer == NULL) {
            [self.displayLink setPaused:YES];
            [self.inputStream close];
            //            NSLog(@"数据已经读完了");
            return;
        }
        
        // 3. 解码 H264大端数据 数据是在内存中,系统端数据
        uint32_t nalSize = (uint32_t)(packetSize - 4);
        uint32_t *pNAL = (uint32_t *)packetBuffer;
        *pNAL = CFSwapInt32HostToBig(nalSize);
        
        // 4. 获取类型 sps: 0x27 pps:0x28 IDR:0x25
        int nalType = packetBuffer[4] & 0x1F;
        switch (nalType) {
            case 0x07:
                //                NSLog(@"SPS数据");
                spsSize = packetSize - 4;
                pSPS = malloc(spsSize);
                memcpy(pSPS, packetBuffer, spsSize);
                break;
                
            case 0x08:
                //                NSLog(@"pps数据");
                ppsSize = packetSize - 4;
                pPPS = malloc(spsSize);
                memcpy(pPPS, packetBuffer, ppsSize);
                break;
                
            case 0x05:
                //                NSLog(@"idr数据");
                // 1. 创建VTDecompressionSessionRef
                [self initDecompressionSession];
                
                // 2. 解码i帧
                [self decodeFrame];
                break;
                
            default:
                //                NSLog(@"B/P数据");
                [self decodeFrame];
                break;
        }
    });
}


#pragma mark - 从文件中读取一个NALU的数据



- (void)readPacket {
    // 1. 第二次读取的时候,必须保证之前的数据被清除掉
    if (packetSize || packetBuffer) {
        packetSize = 0;
        packetBuffer = nil;
    }
    
    // 2. 读取数据
    if (inputSize < inputMaxSize && _inputStream.hasBytesAvailable) {
        inputSize += [self.inputStream read:inputBuffer + inputSize maxLength:inputMaxSize - inputSize];
    }
    
    // 3. 获取解码想要的数据 0x 00 00 00 01
    if (memcmp(inputBuffer, pStartCode, 4) == 0) {
        uint8_t *pStart = inputBuffer + 4;
        uint8_t *pEnd = inputBuffer + inputSize;
        while (pStart != pEnd) {
            if (memcmp(pStart - 3, pStartCode, 4) == 0) {
                // 获取下一个 0x 00 00 00 01
                packetSize = pStart - 3 - inputBuffer;
                
                // 从inputBuffer中拷贝数据到packetBuffer
                packetBuffer = malloc(packetSize);
                memcpy(packetBuffer, inputBuffer, packetSize);
                
                // 将数据移动到最前面
                memmove(inputBuffer, inputBuffer + packetSize, inputSize - packetSize);
                
                // 改变inputSize的大小
                inputSize -= packetSize;
                
                break;
            } else {
                pStart++;
            }
        }
    }
}


#pragma mark - 初始化VTDecompressionSession
- (void)initDecompressionSession {
    // 1. 创建CMVideoFormatDescriptionRef
    const uint8_t *pParamSet[2] = {pSPS, pPPS};
    uint8_t pParamSizes[2] = {spsSize, ppsSize};
    CMVideoFormatDescriptionRef formatDescription;
    CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, pParamSet, pParamSizes, 4, &formatDescription);
    
    // 2. 创建VTDecompressionSessionRef
    NSDictionary *attrs = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decodeCallBack;
    VTDecompressionSessionCreate(NULL, formatDescription, NULL, (__bridge CFDictionaryRef)attrs, &callBackRecord, &_decompressionSession);
}

void decodeCallBack(void * CM_NULLABLE decompressionOutputRefCon,
                    void * CM_NULLABLE sourceFrameRefCon,
                    OSStatus status,
                    VTDecodeInfoFlags infoFlags,
                    CM_NULLABLE CVImageBufferRef imageBuffer,
                    CMTime presentationTimeStamp,
                    CMTime presentationDuration ) {
    
}

#pragma mark - 解码数据
- (void)decodeFrame {
    
}
@end
