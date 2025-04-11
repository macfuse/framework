//
//  GMDirectoryEntry.h
//  macFUSE
//

//  Copyright (c) 2025 Benjamin Fleischer.
//  All rights reserved.

#import <Foundation/Foundation.h>

#import <macFUSE/GMAvailability.h>

// See "64-bit Class and Instance Variable Access Control"
#define GM_EXPORT __attribute__((visibility("default")))

NS_ASSUME_NONNULL_BEGIN

GM_AVAILABLE(5_0) GM_EXPORT @interface GMDirectoryEntry : NSObject

+ (instancetype)directoryEntryWithName:(NSString *)name
                            attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes GM_AVAILABLE(5_0);

- (instancetype)initWithName:(NSString *)name
                  attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes GM_AVAILABLE(5_0);

@property (nonatomic, readonly, copy) NSString *name GM_AVAILABLE(5_0);
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *attributes GM_AVAILABLE(5_0);

@end

#undef GM_EXPORT

NS_ASSUME_NONNULL_END
