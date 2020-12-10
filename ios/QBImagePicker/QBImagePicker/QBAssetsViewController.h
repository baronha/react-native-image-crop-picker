//
//  QBAssetsViewController.h
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QBImagePickerController;
@class PHAssetCollection;

@interface QBAssetsViewController : UICollectionViewController

@property (nonatomic, weak) QBImagePickerController *imagePickerController;
@property (nonatomic, strong) PHAssetCollection *assetCollection;
@property (nonatomic, copy) NSArray *fetchResults;
@property (nonatomic, copy) NSArray *assetCollections;
@property (nonatomic, copy) NSString *albumTitle;
@property (nonatomic, assign) BOOL haveVideo;


@end
