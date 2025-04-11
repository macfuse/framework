//
//  GMDirectoryEntry.m
//  macFUSE
//

//  Copyright (c) 2025 Benjamin Fleischer.
//  All rights reserved.

#import "GMDirectoryEntry.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@implementation GMDirectoryEntry

@synthesize name = _name;
@synthesize attributes = _attributes;

+ (instancetype)directoryEntryWithName:(NSString *)name
                            attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes {
    return [[[self alloc] initWithName:name attributes:attributes] autorelease];
}

- (instancetype)initWithName:(NSString *)name
                  attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes {
    self = [super init];
    if (self) {
        _name = [name copy];
        _attributes = [attributes copy];
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [_attributes release];
    [super dealloc];
}

@end

NS_ASSUME_NONNULL_END
