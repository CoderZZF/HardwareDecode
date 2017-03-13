//
//  ViewController.m
//  硬解码
//
//  Created by zhangzhifu on 2017/3/13.
//  Copyright © 2017年 seemygo. All rights reserved.
//

#import "ViewController.h"

const char pStartCode[] = "\x00\x00\x00\x01";

@interface ViewController ()
{
    long inputMaxSize;
    long inputSize;
    uint8_t *inputBuffer;
    
    long packetSize;
    uint8_t *packetBuffer;
}
@property (nonatomic, weak) CADisplayLink *displayLink;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) dispatch_queue_t queue;
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
    
    
    // 开启定时器
    [self.displayLink setPaused:NO];
}


// 开始读取数据
- (void)updateFrame {
    dispatch_sync(_queue, ^{
        // 1. 读取数据
        [self readPacket];
        
        // 2. 判断数据的类型
        
        // 3. 解码
    });
}


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
            if (memcmp(pStart - 3, pStartCode, 4)) {
                // 获取下一个 0x 00 00 00 01
                packetSize = pStart - 3 - inputBuffer;
                
                // 从inputBuffer中拷贝数据到packetBuffer
                memcpy(packetBuffer, inputBuffer, packetSize);
                
                // 将数据移动到最前面
                memmove(inputBuffer, inputBuffer + packetSize, inputSize - packetSize);
                
                // 改变inputSize的大小
                inputSize -= packetSize;
            } else {
                pStart++;
            }
        }
    }
    
    
    
}
@end
