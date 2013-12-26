//
//  JCViewController.m
//  HeartRateMonitor
//
//  Created by Jesse Collis on 26/12/2013.
//  Copyright (c) 2013 JCMultimedia. All rights reserved.
//

#import "JCViewController.h"

// https://developer.bluetooth.org/gatt/services/Pages/ServicesHome.aspx

#define HRM_DEVICE_INFO_SERVICE @"180A" //org.bluetooth.service.device_information
#define HRM_HEAT_RATE_SERVICE @"180D" //org.bluetooth.service.heart_rate

// https://developer.bluetooth.org/gatt/characteristics/Pages/CharacteristicsHome.aspx

#define HRM_MEASUREMENT_CHARACTERISTIC @"2A37" //org.bluetooth.characteristic.heart_rate_measurement
#define HRM_BODY_LOCATION_CHARACTERISTIC @"2A38" //org.bluetooth.characteristic.blood_pressure_measurement
#define HRM_MANUFACTURER_NAME_CHARACTERISTIC @"2A29" //org.bluetooth.characteristic.manufacturer_name_string

@interface JCViewController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheral *blueHRPeripheral;

@property (nonatomic, strong) IBOutlet UITextView *deviceInfo;
@property (nonatomic, strong) NSString *connected;
@property (nonatomic, strong) NSString *bodyData;
@property (nonatomic, strong) NSString *manufacturer;
@property (nonatomic, strong) NSString *deviceData;
@property (nonatomic, assign) uint16_t heartRate;

@property (nonatomic, strong) IBOutlet UILabel *heartRateBPM;
@property (nonatomic, strong) NSTimer *pulseTimer;

@end

@implementation JCViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSArray *services = @[[CBUUID UUIDWithString:HRM_HEAT_RATE_SERVICE], [CBUUID UUIDWithString:HRM_DEVICE_INFO_SERVICE] ];
    self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    [self.centralManager scanForPeripheralsWithServices:services options:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Characteristic Getter Instance Methods



- (void)getHeartBPMData:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSData *data = characteristic.value;
    //https://developer.bluetooth.org/gatt/characteristics/Pages/CharacteristicViewer.aspx?u=org.bluetooth.characteristic.heart_rate_measurement.xml
    // [8bit-flags [0-format][12-contact-status][3-energry][4-interval][567-NaN][8bit-integer]
    const uint8_t *reportData = [data bytes];
    uint16_t bpm = 0;

    if ((reportData[0] & 0x01) == 0) //Format is set to UINT8
    {
        bpm = reportData[1]; //grab the second byte directly, put it in the bigger container bpm
    }
    else //Format is set to UINT16
    {
        //FIXME: not tested
        uint16_t *pointerToSecondByte = (uint16_t *)(&reportData[1]);
        bpm = CFSwapInt16LittleToHost(*pointerToSecondByte);
    }

    if ((characteristic.value) || !error)
    {
        self.heartRate = bpm;
        self.heartRateBPM.text = [NSString stringWithFormat:@"HR: %i BPM", bpm];
    }
}

- (void)getManufacturerName:(CBCharacteristic *)characteristic
{

}

- (void)getBodyLocation:(CBCharacteristic *)characteristic
{

}

#pragma mark - CBCentralManagerDelegate

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    peripheral.delegate = self;

    NSArray *services = @[ [CBUUID UUIDWithString:HRM_DEVICE_INFO_SERVICE], [CBUUID UUIDWithString:HRM_HEAT_RATE_SERVICE]];
    [peripheral discoverServices:services];
    self.connected = [NSString stringWithFormat:@"connected: %@", peripheral.state == CBPeripheralStateConnected ? @"YES" : @"NO"];
    NSLog(@"%@", self.connected);
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    //TODO: Error case
    NSLog(@"did fail to connect");
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSString *localName = [advertisementData objectForKey:CBAdvertisementDataLocalNameKey];
    //FIXME: JC - Why check for a length?
    if (localName.length > 0)
    {
        NSLog(@"Found the HRM: %@", localName);
        [self.centralManager stopScan];
        self.blueHRPeripheral = peripheral;
        peripheral.delegate = self;
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    switch (central.state)
    {
        case CBCentralManagerStatePoweredOff:
        {
            NSLog(@"CoreBluetooth didUpdateState: hardware is powered off.");
            break;
        }
        case CBCentralManagerStatePoweredOn:
        {
            NSLog(@"CoreBluetooth didUpdateState: hardware is powered on.");
            break;
        }
        case CBCentralManagerStateUnauthorized:
        {
            NSLog(@"CoreBluetooth didUpdateState: unauthorized.");
            break;
        }
        case CBCentralManagerStateResetting:
        {
            NSLog(@"CoreBluetooth didUpdateState: hardware is resetting.");
            break;
        }
        case CBCentralManagerStateUnsupported:
        {
            NSLog(@"CoreBluetooth didUpdateState: hardware is unsupported.");
            break;
        }
        default:
        case CBCentralManagerStateUnknown:
        {
            NSLog(@"CoreBluetooth didUpdateState: state is unknown.");
            break;
        }
    }

}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    for (CBService *service in peripheral.services)
    {
        NSArray *chars;
        if ([service.UUID isEqual:[CBUUID UUIDWithString:HRM_DEVICE_INFO_SERVICE]])
        {
            chars = @[[CBUUID UUIDWithString:HRM_MANUFACTURER_NAME_CHARACTERISTIC]];

        }
        else if ([service.UUID isEqual:[CBUUID UUIDWithString:HRM_HEAT_RATE_SERVICE]])
        {
            chars = @[[CBUUID UUIDWithString:HRM_MEASUREMENT_CHARACTERISTIC],
                      [CBUUID UUIDWithString:HRM_BODY_LOCATION_CHARACTERISTIC]];
        }

        [peripheral discoverCharacteristics:chars forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{

    NSAssert(peripheral == self.blueHRPeripheral, @"I'm expecting the peripheral is the same as the one I was using before");

    //FIXME: JC - I subscribed explicitly to these characteristics. I shouldn't have to check them twice, except for the case
    // where I want to setNotifyValue instead of readValue;

    if ([service.UUID isEqual:[CBUUID UUIDWithString:HRM_DEVICE_INFO_SERVICE]])
    {
        for (CBCharacteristic *aChar in service.characteristics)
        {
            if ([aChar.UUID isEqual:[CBUUID UUIDWithString:HRM_MANUFACTURER_NAME_CHARACTERISTIC]])
            {
                [peripheral readValueForCharacteristic:aChar];
            }
        }
    }
    else if ([service.UUID isEqual:[CBUUID UUIDWithString:HRM_HEAT_RATE_SERVICE]])
    {
        for (CBCharacteristic *aChar in service.characteristics)
        {
            if ([aChar.UUID isEqual:[CBUUID UUIDWithString:HRM_MEASUREMENT_CHARACTERISTIC]])
            {
                [peripheral setNotifyValue:YES forCharacteristic:aChar];
            }
            else if ([aChar.UUID isEqual:[CBUUID UUIDWithString:HRM_BODY_LOCATION_CHARACTERISTIC]])
            {
                [peripheral readValueForCharacteristic:aChar];
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:HRM_MEASUREMENT_CHARACTERISTIC]])
    {
        [self getHeartBPMData:characteristic error:error];
    }
    else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:HRM_MANUFACTURER_NAME_CHARACTERISTIC]])
    {
        [self getManufacturerName:characteristic];
    }
    else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:HRM_BODY_LOCATION_CHARACTERISTIC]])
    {
        [self getBodyLocation:characteristic];
    }

    self.deviceInfo.text = [NSString stringWithFormat:@"%@\n%@\n%@\n", self.connected, self.bodyData, self.manufacturer];
}

@end
