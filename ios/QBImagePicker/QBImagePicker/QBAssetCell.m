//
//  QBAssetCell.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBAssetCell.h"

@interface QBAssetCell ()

@property (weak, nonatomic) IBOutlet UIView *overlayView;

@end

@implementation QBAssetCell

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    
    // Show/hide overlay view
    self.overlayView.hidden = !(selected && self.showsOverlayViewWhenSelected);
    self.overlayView.layer.borderWidth = 3;
    self.overlayView.layer.borderColor = [UIColor colorWithRed:255.0 / 255.0 green:175.0 / 255.0 blue:0.0 / 255.0 alpha:1.0].CGColor;
}

@end
