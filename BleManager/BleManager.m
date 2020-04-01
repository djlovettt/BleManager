//
//  BleManager.m
//  HydraulicSystem
//
//  Created by larva on 2020/2/28.
//  Copyright © 2020 transcosmos. All rights reserved.
//

#import "BleManager.h"

@interface BleManager() <CBCentralManagerDelegate,CBPeripheralDelegate>

@property (strong, nonatomic) CBCentralManager *centralManager;           /// 中央管理者
@property (strong, nonatomic) CBPeripheral     *connectingPeripheral;     /// 处于连接状态的蓝牙设备
@property (strong, nonatomic) CBCharacteristic *writeValueCharacteristic; /// 可写入特征值
@property (strong, nonatomic) NSTimer          *connectionTimer;          /// 设备接续计时器
@property (strong, nonatomic) NSArray        <CBUUID *> *targetPeripheralUUIDs;  /// 筛选蓝牙设备的 UUID 集合
@property (strong, nonatomic) NSMutableArray <NSData *> *waitingToAppendDatas;   /// 存储待拼接的数据
@property (strong, nonatomic) NSMutableArray <CBPeripheral *> *discoverdDevices; /// 存储已检索到的蓝牙设备
@end

@implementation BleManager

/// 初期化 BleManager 单例对象
static BleManager *manager = nil;
+ (instancetype)sharedInstance {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[BleManager alloc] init];
        [manager initObjects];
    });
    return manager;
}

/// 检索设备
- (void)scanPeripherals {
    
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        [self errorMsgCallBack:@"蓝牙不可用"];
        return;
    }
    [self.discoverdDevices removeAllObjects];
    if (self.scanDevicesBlock) {
        self.scanDevicesBlock(self.discoverdDevices);
    }
    [self.centralManager scanForPeripheralsWithServices:self.targetPeripheralUUIDs options:nil];
}

/// 停止检索
- (void)stopScan {
    
    [self.centralManager stopScan];
}

/// 连接设备
/// @param peripheral 蓝牙设备
- (void)connectPeripheral:(CBPeripheral *)peripheral {
    
    if (!peripheral) {
        [self errorMsgCallBack:@"请检查与蓝牙设备的连接状态"];
        return;
    }
    NSLog(@"BleManager --> 即将建立与 %@ 的连接", peripheral);
    [self.centralManager connectPeripheral:peripheral options:nil];
    
    /// 开启接续计时器
    if (!self.connectionTimer) {
        __weak typeof(self) weakSelf = self;
        self.connectionTimer = [NSTimer scheduledTimerWithTimeInterval:self.connectionDuration repeats:NO block:^(NSTimer * _Nonnull timer) {
            
            if (!weakSelf.connectingPeripheral) {
                [weakSelf invalidateConnectionTimer];
                [weakSelf cancelPeripheralConnection:peripheral];
                [weakSelf errorMsgCallBack:@"连接失败，请重试"];
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.connectionTimer forMode:NSRunLoopCommonModes];
    }
}

/// 断开连接
/// @param peripheral 蓝牙设备
- (void)cancelPeripheralConnection:(CBPeripheral *)peripheral {
    
    if (!peripheral) {
        [self errorMsgCallBack:@"没有已连接的设备"];
        return;
    }
    NSLog(@"BleManager --> 即将断开与 %@ 的连接", peripheral);
    [self.centralManager cancelPeripheralConnection:peripheral];
}

/// 写入数据
/// @param data 待写入的数据
- (void)writeValue:(NSData *)data {
    
    NSLog(@"BleManager --> 准备发送数据 %@", [self dataToDictionary:data]);
    
    if (!data.length) {
        NSLog(@"BleManager --> 数据发送失败，待发送数据不能为空");
        [self errorMsgCallBack:@"待发送的数据为空"];
        return;
    }
    if (!self.connectingPeripheral) {
        NSLog(@"BleManager --> 数据发送失败，没有正在连接的设备");
        [self errorMsgCallBack:@"没有已连接的设备"];
        return;
    }
    if (!self.writeValueCharacteristic) {
        NSLog(@"BleManager --> 数据发送失败，没有可写入的特征值");
        [self errorMsgCallBack:@"无法向蓝牙设备写入数据"];
        return;
    }
    [self.connectingPeripheral writeValue:data forCharacteristic:self.writeValueCharacteristic type:CBCharacteristicWriteWithResponse];
}

#pragma mark -

- (void)centralManagerDidUpdateState:(nonnull CBCentralManager *)central {
    
    switch (central.state) {
        case CBManagerStateResetting:
            [self errorMsgCallBack:@"蓝牙重置中"];
            [self stopScan];
            break;
        case CBManagerStateUnsupported:
            [self errorMsgCallBack:@"设备不支持蓝牙"];
            break;
        case CBManagerStateUnauthorized:
            NSLog(@"BleManager --> 未授权...");
            [self errorMsgCallBack:@"请开启蓝牙权限"];
            break;
        case CBManagerStatePoweredOff:
            NSLog(@"BleManager --> 蓝牙未开启...");
            [self errorMsgCallBack:@"请开启蓝牙"];
            break;
        case CBManagerStatePoweredOn:
            NSLog(@"BleManager --> 蓝牙已开启...");
            break;
        default:
            // CBManagerStateUnknown
            NSLog(@"BleManager --> 未知错误...");
            [self errorMsgCallBack:@"未知错误，请重新开启蓝牙"];
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    
    // 检索到设备
    if (peripheral.name.length && ![self.discoverdDevices containsObject:peripheral]) {
        
        [self.discoverdDevices addObject:peripheral];
        if (self.scanDevicesBlock) {
            self.scanDevicesBlock(self.discoverdDevices);
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    
    NSLog(@"BleManager --> didConnectPeripheral -> %@", peripheral);
    // 已连接
    self.connectingPeripheral = peripheral;
    // start to discover services
    self.connectingPeripheral.delegate = self;
    [self.connectingPeripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    NSLog(@"BleManager --> didFailToConnectPeripheral -> %@", peripheral);
    // 连接失败
    self.connectingPeripheral     = nil;
    self.writeValueCharacteristic = nil;
    
    if (self.connectResultBlock) {
        self.connectResultBlock(nil);
        [self invalidateConnectionTimer];
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    NSLog(@"BleManager --> didDisconnectPeripheral -> %@", peripheral);
    // 已断开连接
    self.connectingPeripheral     = nil;
    self.writeValueCharacteristic = nil;
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    
    // 发现服务
    for (CBService *service in peripheral.services) {
        // start to discover characteristics
        NSLog(@"BleManager --> didDiscoverServices -> %@", service);
        [self.connectingPeripheral discoverCharacteristics:nil forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    
    // 发现特征值
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"BleManager --> didDiscoverCharacteristicsForService -> %@", characteristic);
        
        // 写数据特征值
        if ([characteristic.UUID.UUIDString isEqualToString:@"***"]) {
            
            self.writeValueCharacteristic = characteristic;
            // 扫描到可写入的特征值后认为设备连接成功
            if (self.connectResultBlock) {
                [self invalidateConnectionTimer];
                self.connectResultBlock(peripheral);
            }
            NSLog(@"BleManager --> 已发现可写入的特征值  %@", self.writeValueCharacteristic);
        }
        
        // 监听数据特征值
        if ([characteristic.UUID.UUIDString isEqualToString:@"***"]) {
            
            [self.connectingPeripheral setNotifyValue:YES forCharacteristic:characteristic];
            [self.connectingPeripheral readValueForCharacteristic:characteristic];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    // 向某一特征值写指令
    NSLog(@"BleManager --> didWriteValueForCharacteristic -> %@  %@", characteristic, [self dataToDictionary:characteristic.value]);
    if (error) {
        [self errorMsgCallBack:@"数据写入失败"];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    if (!characteristic.value.length) { return; }
    
    // 接收到某一特征值返回的数据
    NSLog(@"BleManager --> didUpdateValueForCharacteristic -> %@  %@", characteristic, [self dataToDictionary:characteristic.value]);
    
    // 数据校验失败
    if (![self checkData:characteristic.value]) {
        NSLog(@"BleManager --> 接收到的数据不完整，等待拼接");
        [self.waitingToAppendDatas addObject:characteristic.value];
        return;
    }
    
    NSMutableData *fullData = [[NSMutableData alloc] init];
    if (self.waitingToAppendDatas.count) {
        // 若存在不完整数据，则拼接数据
        for (NSData *waitToAppendData in self.waitingToAppendDatas) {
            [fullData appendData:waitToAppendData];
        }
    }
    [fullData appendData:characteristic.value];
    
    if (self.receiveDataBlock) {
        // 传递完整数据后，清空待拼接数据
        [self.waitingToAppendDatas removeAllObjects];
        self.receiveDataBlock([self dataToDictionary:fullData]);
    }
}

#pragma mark -

/// 验证是否接收到数据尾
/// @param data 待验证的数据
- (BOOL)checkData:(NSData *)data {
    
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"BleManager --> checkDataIntegrity %@", jsonString);
    
    return [jsonString hasSuffix:@"}}"];
}

/// NSData 转 NSDictionary
/// @param data 待转换数据
- (NSDictionary *)dataToDictionary:(NSData *)data {
    
    if (!data.length) { return nil; }
    
    NSString *receiveString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"dataToDictionary --> %@", receiveString);
    if (!receiveString) {
        return nil;
    }
    NSData *encodingData = [receiveString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:encodingData options:NSJSONReadingMutableLeaves error:nil];
    return dictionary;
}

#pragma mark -

/// 初期化
- (void)initObjects {
    
    self.connectionDuration    = 5.0;
    self.discoverdDevices      = [[NSMutableArray alloc] init];
    self.waitingToAppendDatas  = [[NSMutableArray alloc] init];
    self.targetPeripheralUUIDs = @[[CBUUID UUIDWithString:@"***"], [CBUUID UUIDWithString:@"***"]];
    self.centralManager        = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue() options:nil];
}

/// 设置最长接续时间
/// @param connectionDuration 最长接续时间
- (void)setConnectionDuration:(NSTimeInterval)connectionDuration {
    
    _connectionDuration = connectionDuration;
}

/// 注销接续计时器
- (void)invalidateConnectionTimer {
    
    [self.connectionTimer invalidate];
    self.connectionTimer = nil;
}

/// 错误回调
/// @param error 错误信息
- (void)errorMsgCallBack:(NSString *)error {
    
    if (!error.length) { return; }
    
    if (self.errorMsgBlock) {
        self.errorMsgBlock(error);
    }
}

@end
