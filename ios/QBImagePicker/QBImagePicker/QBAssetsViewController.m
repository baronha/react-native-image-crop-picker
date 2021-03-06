//
//  QBAssetsViewController.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBAssetsViewController.h"
#import "QBAlbumsViewController.h"
#import <Photos/Photos.h>

// Views
#import "QBImagePickerController.h"
#import "QBAssetCell.h"
#import "QBVideoIndicatorView.h"

static CGSize CGSizeScale(CGSize size, CGFloat scale) {
    return CGSizeMake(size.width * scale, size.height * scale);
}

@interface QBImagePickerController (Private)

@property (nonatomic, strong) NSBundle *assetBundle;

@end

@implementation NSIndexSet (Convenience)

- (NSArray *)qb_indexPathsFromIndexesWithSection:(NSUInteger)section
{
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:self.count];
    [self enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForItem:idx inSection:section]];
    }];
    return indexPaths;
}

@end

@implementation UICollectionView (Convenience)

- (NSArray *)qb_indexPathsForElementsInRect:(CGRect)rect
{
    NSArray *allLayoutAttributes = [self.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}

@end

@interface QBAssetsViewController () <PHPhotoLibraryChangeObserver, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) IBOutlet UIButton *doneButton;
@property (nonatomic, strong) IBOutlet UIButton *backButton;

@property (nonatomic, strong) PHFetchResult *fetchResult;

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, assign) CGRect previousPreheatRect;

@property (nonatomic, assign) BOOL disableScrollToBottom;
@property (nonatomic, strong) NSIndexPath *lastSelectedItemIndexPath;
@property (nonatomic, strong) UINavigationController *albumsNavigationController;


@end

@implementation QBAssetsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self initAssets];
    [self setUpToolbarItems];
    [self resetCachedAssets];
    
    // Register observer
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Configure collection view
    self.albumTitle = @"Hình ảnh";
    [self setUpNavigationBar];
    self.collectionView.allowsMultipleSelection = self.imagePickerController.allowsMultipleSelection;
    [self.collectionView reloadData];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    // Save indexPath for the last item
    NSIndexPath *indexPath = [[self.collectionView indexPathsForVisibleItems] lastObject];
    
    // Update layout
    [self.collectionViewLayout invalidateLayout];
    
    // Restore scroll position
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    }];
}

- (void)dealloc
{
    // Deregister observer
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}


#pragma mark - Accessors

- (void)setAssetCollection:(PHAssetCollection *)assetCollection
{
    _assetCollection = assetCollection;
    [self updateFetchRequest];
}

- (PHCachingImageManager *)imageManager
{
    if (_imageManager == nil) {
        _imageManager = [PHCachingImageManager new];
    }
    
    return _imageManager;
}

- (BOOL)isAutoDeselectEnabled
{
    return (self.imagePickerController.maximumNumberOfSelection == 1
            && self.imagePickerController.maximumNumberOfSelection >= self.imagePickerController.minimumNumberOfSelection);
}


#pragma mark - Actions

- (void)done:(UITapGestureRecognizer *)tapGesture
{
    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didFinishPickingAssets:)]) {
        [self.imagePickerController.delegate qb_imagePickerController:self.imagePickerController
                                               didFinishPickingAssets:self.imagePickerController.selectedAssets.array];
    }
}

- (void)onBack:(UITapGestureRecognizer *)tapGesture {
    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerControllerDidCancel:)]) {
        [self.imagePickerController.delegate qb_imagePickerControllerDidCancel:self.imagePickerController];
    }
}

- (void)chooseAlbum:(UITapGestureRecognizer *)tapGesture {
    UIStoryboard *story = [UIStoryboard storyboardWithName:@"QBImagePicker" bundle:self.imagePickerController.assetBundle];
    
    UINavigationController *albumsViewController = [story instantiateViewControllerWithIdentifier:@"QBAlbumsNavigationController"];
    
    albumsViewController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:albumsViewController animated:YES completion:nil];
}



#pragma mark - TopNavigator

-(void)setUpNavigationBar
{
    UINavigationBar* navigationbar = self.navigationController.navigationBar;
    
    UINavigationItem* navigationItem = [[UINavigationItem alloc] init];
    
    if (@available(iOS 9.0, *)) {
        //handle subTitle
        UILabel *title = [[UILabel alloc]init];
        UILabel *subtitle = [[UILabel alloc]init];
        
        [title setFont:[UIFont systemFontOfSize:12]];
        [title setTextColor:[UIColor whiteColor]];
        [title setFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
        [title sizeToFit];
        title.text = _albumTitle;
        if (@available(iOS 13.0, *)) {
            title.textColor = [UIColor labelColor];
        } else {
            title.textColor = [UIColor blackColor];
        }
        
        [subtitle setTextColor:[UIColor whiteColor]];
        [subtitle setFont:[UIFont systemFontOfSize:12]];
        [subtitle setTextAlignment:NSTextAlignmentCenter];
        [subtitle sizeToFit];
        subtitle.text = @"Thay đổi albums";
        subtitle.textColor = [UIColor grayColor];
        
        //stackView
        UIStackView *stackVw = [[UIStackView alloc]initWithArrangedSubviews:@[title,subtitle]];
        stackVw.distribution = UIStackViewDistributionEqualCentering;
        stackVw.axis = UILayoutConstraintAxisVertical;
        stackVw.alignment = UIStackViewAlignmentCenter;
        [stackVw setFrame:CGRectMake(0, 0, MAX(title.frame.size.width, subtitle.frame.size.width), 0)];
        stackVw.userInteractionEnabled = true;
        UITapGestureRecognizer *tapGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(chooseAlbum:)];
        [stackVw addGestureRecognizer:tapGesture];
        
        navigationItem.titleView = stackVw;
    }else{
        navigationItem.title = _albumTitle;
    }
    
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"Thoát"
                                                                   style:UIBarButtonItemStylePlain
                                                                  target:self
                                                                  action:@selector(onBack:)];
    cancelItem.tintColor = [UIColor systemPinkColor];
    navigationItem.leftBarButtonItem = cancelItem;
    navigationbar.items = [NSArray arrayWithObjects: navigationItem,nil];
    [navigationbar setItems:@[navigationItem]];
}

#pragma mark - Toolbar

- (void)setUpToolbarItems
{
//    // Space
//    UIBarButtonItem *leftSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
//    UIBarButtonItem *rightSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    
    //tap
    UITapGestureRecognizer *doneTap =
      [[UITapGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(done:)];
    
    UIView *buttonDoneView = [[UIView alloc] initWithFrame:CGRectMake(0, 24,0 , 48)];
    
    UILabel *titleButtonDone = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] applicationFrame].size.width, 48)];

    titleButtonDone.text = @"Hoàn tất";
    [titleButtonDone setFont:[UIFont systemFontOfSize:12]];
    [titleButtonDone setTextColor:[UIColor whiteColor]];
    if (@available(iOS 8.2, *)) {
        [titleButtonDone setFont:[UIFont systemFontOfSize:14 weight:UIFontWeightBold]];
    }
    titleButtonDone.textAlignment = NSTextAlignmentCenter;
    //view
    buttonDoneView.layer.backgroundColor = [UIColor colorWithRed:255.0 / 255.0 green:175.0 / 255.0 blue:0.0 / 255.0 alpha:1.0].CGColor;
    buttonDoneView.layer.cornerRadius = 6;
    
    [buttonDoneView addSubview:titleButtonDone];
    [buttonDoneView addGestureRecognizer:doneTap];
    
    
    UIBarButtonItem *buttonDone = [[UIBarButtonItem alloc] initWithCustomView:buttonDoneView];

    self.toolbarItems = @[buttonDone];
}

//- (void)updateSelectionInfo
//{
//    NSMutableOrderedSet *selectedAssets = self.imagePickerController.selectedAssets;
//
//    if (selectedAssets.count > 0) {
//        NSBundle *bundle = self.imagePickerController.assetBundle;
//        NSString *format;
//        if (selectedAssets.count > 1) {
//            format = NSLocalizedStringFromTableInBundle(@"assets.toolbar.items-selected", @"QBImagePicker", bundle, nil);
//        } else {
//            format = NSLocalizedStringFromTableInBundle(@"assets.toolbar.item-selected", @"QBImagePicker", bundle, nil);
//        }
//
//        NSString *title = [NSString stringWithFormat:format, selectedAssets.count];
//        [(UIBarButtonItem *)self.toolbarItems[1] setTitle:title];
//    } else {
//        [(UIBarButtonItem *)self.toolbarItems[1] setTitle:@""];
//    }
//}


#pragma mark - Fetching Assets
-(PHFetchOptions *) handleOptions
{
    PHFetchOptions *options = [PHFetchOptions new];
    
    
    
    switch (self.imagePickerController.mediaType) {
        case QBImagePickerMediaTypeImage:
            options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeImage];
            break;
            
        case QBImagePickerMediaTypeVideo:
            options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeVideo];
            break;
            
        default:
            options.predicate = [NSPredicate predicateWithFormat:@"duration < 60"];
            break;
    }
    
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending: NO]];
    
    return options;
}

- (void)updateFetchRequest
{
    if (self.assetCollection) {
        PHFetchOptions *options = (PHFetchOptions *)self.handleOptions;
        
        self.fetchResult = [PHAsset fetchAssetsInAssetCollection:self.assetCollection options:options];
        
        if ([self isAutoDeselectEnabled] && self.imagePickerController.selectedAssets.count > 0) {
            // Get index of previous selected asset
            PHAsset *asset = [self.imagePickerController.selectedAssets firstObject];
            NSInteger assetIndex = [self.fetchResult indexOfObject:asset];
            self.lastSelectedItemIndexPath = [NSIndexPath indexPathForItem:assetIndex inSection:0];
        }
    } else {
        self.fetchResult = nil;
    }
}


-(void)initAssets
{
    PHFetchOptions *options = self.handleOptions;
    
    PHFetchResult *result = [PHAsset fetchAssetsWithOptions:options];
    self.fetchResult = [result copy];
}

#pragma mark - Checking for Selection Limit

- (BOOL)isMinimumSelectionLimitFulfilled
{
    return (self.imagePickerController.minimumNumberOfSelection <= self.imagePickerController.selectedAssets.count);
}

- (BOOL)isMaximumSelectionLimitReached
{
    NSUInteger minimumNumberOfSelection = MAX(1, self.imagePickerController.minimumNumberOfSelection);
    
    if (minimumNumberOfSelection <= self.imagePickerController.maximumNumberOfSelection) {
        return (self.imagePickerController.maximumNumberOfSelection <= self.imagePickerController.selectedAssets.count);
    }
    
    return NO;
}



#pragma mark - Asset Caching

- (void)resetCachedAssets
{
    [self.imageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets
{
    BOOL isViewVisible = [self isViewLoaded] && self.view.window != nil;
    if (!isViewVisible) { return; }
    
    // The preheat window is twice the height of the visible rect
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0, -0.5 * CGRectGetHeight(preheatRect));
    
    // If scrolled by a "reasonable" amount...
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0) {
        // Compute the assets to start caching and to stop caching
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self.collectionView qb_indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        } removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self.collectionView qb_indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        }];
        
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        
        CGSize itemSize = [(UICollectionViewFlowLayout *)self.collectionViewLayout itemSize];
        CGSize targetSize = CGSizeScale(itemSize, [[UIScreen mainScreen] scale]);
        
        [self.imageManager startCachingImagesForAssets:assetsToStartCaching
                                            targetSize:targetSize
                                           contentMode:PHImageContentModeAspectFill
                                               options:nil];
        [self.imageManager stopCachingImagesForAssets:assetsToStopCaching
                                           targetSize:targetSize
                                          contentMode:PHImageContentModeAspectFill
                                              options:nil];
        
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect addedHandler:(void (^)(CGRect addedRect))addedHandler removedHandler:(void (^)(CGRect removedRect))removedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths
{
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.item < self.fetchResult.count) {
            PHAsset *asset = self.fetchResult[indexPath.item];
            [assets addObject:asset];
        }
    }
    return assets;
}


#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    dispatch_async(dispatch_get_main_queue(), ^{
        PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:self.fetchResult];
        
        if (collectionChanges) {
            // Get the new fetch result
            self.fetchResult = [collectionChanges fetchResultAfterChanges];
            
            if (![collectionChanges hasIncrementalChanges] || [collectionChanges hasMoves]) {
                // We need to reload all if the incremental diffs are not available
                [self.collectionView reloadData];
            } else {
                // If we have incremental diffs, tell the collection view to animate insertions and deletions
                [self.collectionView performBatchUpdates:^{
                    NSIndexSet *removedIndexes = [collectionChanges removedIndexes];
                    if ([removedIndexes count]) {
                        [self.collectionView deleteItemsAtIndexPaths:[removedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                    
                    NSIndexSet *insertedIndexes = [collectionChanges insertedIndexes];
                    if ([insertedIndexes count]) {
                        [self.collectionView insertItemsAtIndexPaths:[insertedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                    
                    NSIndexSet *changedIndexes = [collectionChanges changedIndexes];
                    if ([changedIndexes count]) {
                        [self.collectionView reloadItemsAtIndexPaths:[changedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                } completion:NULL];
            }
            
            [self resetCachedAssets];
        }
    });
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateCachedAssets];
}


#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.fetchResult.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    QBAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AssetCell" forIndexPath:indexPath];
    cell.tag = indexPath.item;
    cell.showsOverlayViewWhenSelected = self.imagePickerController.allowsMultipleSelection;
    
    // Image
    PHAsset *asset = self.fetchResult[indexPath.item];
    CGSize itemSize = [(UICollectionViewFlowLayout *)collectionView.collectionViewLayout itemSize];
    CGSize targetSize = CGSizeScale(itemSize, [[UIScreen mainScreen] scale]);
    
    [self.imageManager requestImageForAsset:asset
                                 targetSize:targetSize
                                contentMode:PHImageContentModeAspectFill
                                    options:nil
                              resultHandler:^(UIImage *result, NSDictionary *info) {
        if (cell.tag == indexPath.item) {
            cell.imageView.image = result;
        }
    }];
    
    // Video indicator
    if (asset.mediaType == PHAssetMediaTypeVideo) {
        cell.videoIndicatorView.hidden = NO;
        
        NSInteger minutes = (NSInteger)(asset.duration / 60.0);
        NSInteger seconds = (NSInteger)ceil(asset.duration - 60.0 * (double)minutes);
        cell.videoIndicatorView.timeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
        
        if (asset.mediaSubtypes & PHAssetMediaSubtypeVideoHighFrameRate) {
            cell.videoIndicatorView.videoIcon.hidden = YES;
            cell.videoIndicatorView.slomoIcon.hidden = NO;
        }
        else {
            cell.videoIndicatorView.videoIcon.hidden = NO;
            cell.videoIndicatorView.slomoIcon.hidden = YES;
        }
    } else {
        cell.videoIndicatorView.hidden = YES;
    }
    
    // Selection state
    if ([self.imagePickerController.selectedAssets containsObject:asset]) {
        [cell setSelected:YES];
        QBImagePickerController *imagePickerController = self.imagePickerController;
        NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
        NSUInteger i = [ selectedAssets indexOfObject: asset ];
        cell.badge.text = [NSString stringWithFormat:@"%ld", i + 1];
        [collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    }
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if (kind == UICollectionElementKindSectionFooter) {
        UICollectionReusableView *footerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                                  withReuseIdentifier:@"FooterView"
                                                                                         forIndexPath:indexPath];
        
        // Number of assets
        UILabel *label = (UILabel *)[footerView viewWithTag:1];
        
        NSBundle *bundle = self.imagePickerController.assetBundle;
        NSUInteger numberOfPhotos = [self.fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeImage];
        NSUInteger numberOfVideos = [self.fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeVideo];
        
        switch (self.imagePickerController.mediaType) {
            case QBImagePickerMediaTypeAny:
            {
                NSString *format;
                if (numberOfPhotos == 1) {
                    if (numberOfVideos == 1) {
                        format = NSLocalizedStringFromTableInBundle(@"assets.footer.photo-and-video", @"QBImagePicker", bundle, nil);
                    } else {
                        format = NSLocalizedStringFromTableInBundle(@"assets.footer.photo-and-videos", @"QBImagePicker", bundle, nil);
                    }
                } else if (numberOfVideos == 1) {
                    format = NSLocalizedStringFromTableInBundle(@"assets.footer.photos-and-video", @"QBImagePicker", bundle, nil);
                } else {
                    format = NSLocalizedStringFromTableInBundle(@"assets.footer.photos-and-videos", @"QBImagePicker", bundle, nil);
                }
                
                label.text = [NSString stringWithFormat:format, numberOfPhotos, numberOfVideos];
            }
                break;
                
            case QBImagePickerMediaTypeImage:
            {
                NSString *key = (numberOfPhotos == 1) ? @"assets.footer.photo" : @"assets.footer.photos";
                NSString *format = NSLocalizedStringFromTableInBundle(key, @"QBImagePicker", bundle, nil);
                
                label.text = [NSString stringWithFormat:format, numberOfPhotos];
            }
                break;
                
            case QBImagePickerMediaTypeVideo:
            {
                NSString *key = (numberOfVideos == 1) ? @"assets.footer.video" : @"assets.footer.videos";
                NSString *format = NSLocalizedStringFromTableInBundle(key, @"QBImagePicker", bundle, nil);
                
                label.text = [NSString stringWithFormat:format, numberOfVideos];
            }
                break;
        }
        
        return footerView;
    }
    
    return nil;
}


#pragma mark - UICollectionViewDelegate

- (BOOL)allowSelectVideo:(PHAsset *)asset
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Thông báo"
                                                    message:@"Pety chỉ hỗ trợ đăng một Video cho một bài đăng."
                                                   delegate:self
                                          cancelButtonTitle:@"Đồng ý"
                                          otherButtonTitles:nil];
    if(_haveVideo) {
        [alert show];
        return NO;
    }
    QBImagePickerController *imagePickerController = self.imagePickerController;
    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
    
    for(int i = 0;  i < selectedAssets.count; i++){
        PHAsset *item = selectedAssets[i];
        if(item.mediaType == PHAssetMediaTypeVideo){
            [alert show];
            return NO;
        }
    }
    return YES;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    PHAsset *asset = self.fetchResult[indexPath.item];
    if(asset.mediaType == PHAssetMediaTypeVideo){
        return [self allowSelectVideo: asset];
    }
    
    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:shouldSelectAsset:)]) {
       
        return [self.imagePickerController.delegate qb_imagePickerController:self.imagePickerController shouldSelectAsset:asset];
    }
    
    if ([self isAutoDeselectEnabled]) {
        return YES;
    }
    
    return ![self isMaximumSelectionLimitReached];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    QBImagePickerController *imagePickerController = self.imagePickerController;
    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
    PHAsset *asset = self.fetchResult[indexPath.item];
    
    if (imagePickerController.allowsMultipleSelection) {
        if ([self isAutoDeselectEnabled] && selectedAssets.count > 0) {
            // Remove previous selected asset from set
            [selectedAssets removeObjectAtIndex:0];
            
            // Deselect previous selected asset
            if (self.lastSelectedItemIndexPath) {
                [collectionView deselectItemAtIndexPath:self.lastSelectedItemIndexPath animated:NO];
            }
        }
        // Add asset to set
        [selectedAssets addObject:asset];
        
        //setBadge
        QBAssetCell *cell = (QBAssetCell *)[collectionView cellForItemAtIndexPath:indexPath];
        NSUInteger i = [ selectedAssets indexOfObject: asset ];
        cell.badge.text = [NSString stringWithFormat:@"%ld", i + 1];
        
        self.lastSelectedItemIndexPath = indexPath;
        
        if (imagePickerController.showsNumberOfSelectedAssets && selectedAssets.count == 1) {
            [self.navigationController setToolbarHidden:NO animated:YES];
        }
        
    } else {
        if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didFinishPickingAssets:)]) {
            [imagePickerController.delegate qb_imagePickerController:imagePickerController didFinishPickingAssets:@[asset]];
        }
    }
    
    if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didSelectAsset:)]) {
        [imagePickerController.delegate qb_imagePickerController:imagePickerController didSelectAsset:asset];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.imagePickerController.allowsMultipleSelection) {
        return;
    }
    
    QBImagePickerController *imagePickerController = self.imagePickerController;
    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
    
    PHAsset *asset = self.fetchResult[indexPath.item];
    
    // Remove asset from set
    [selectedAssets removeObject:asset];
    [self.collectionView reloadData];
    
    self.lastSelectedItemIndexPath = nil;
    
    if (imagePickerController.showsNumberOfSelectedAssets && selectedAssets.count == 0) {
        [self.navigationController setToolbarHidden:YES animated:YES];
    }
    
    if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didDeselectAsset:)]) {
        [imagePickerController.delegate qb_imagePickerController:imagePickerController didDeselectAsset:asset];
    }
}


#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger numberOfColumns;
    if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
        numberOfColumns = self.imagePickerController.numberOfColumnsInPortrait;
    } else {
        numberOfColumns = self.imagePickerController.numberOfColumnsInLandscape;
    }
    
    CGFloat width = (CGRectGetWidth(self.view.frame) - 2.0 * (numberOfColumns - 1)) / numberOfColumns;
    
    return CGSizeMake(width, width);
}

@end
