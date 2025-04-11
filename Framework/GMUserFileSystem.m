//
//  GMUserFileSystem.m
//  macFUSE
//

//  Copyright (c) 2011-2025 Benjamin Fleischer.
//  All rights reserved.

//  macFUSE.framework is based on MacFUSE.framework. MacFUSE.framework is
//  covered under the following BSD-style license:
//
//  Copyright (c) 2007 Google Inc.
//  All rights reserved.
//
//  Redistribution  and  use  in  source  and  binary  forms,  with  or  without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the  above  copyright  notice,
//     this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//  3. Neither the name of Google Inc. nor the names of its contributors may  be
//     used to endorse or promote products derived from  this  software  without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS  IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT  LIMITED  TO,  THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A  PARTICULAR  PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT  OWNER  OR  CONTRIBUTORS  BE
//  LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,   OR
//  CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT  LIMITED  TO,  PROCUREMENT  OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,  OR  PROFITS;  OR  BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY  THEORY  OF  LIABILITY,  WHETHER  IN
//  CONTRACT, STRICT LIABILITY, OR  TORT  (INCLUDING  NEGLIGENCE  OR  OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  OF  THE
//  POSSIBILITY OF SUCH DAMAGE.

//  Based on FUSEFileSystem originally by alcor.

#import "GMUserFileSystem.h"

#define FUSE_USE_VERSION 26
#include <fuse.h>
#include <fuse/fuse_lowlevel.h>

#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/dirent.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <sys/vnode.h>

#import <Foundation/Foundation.h>
#import "GMDataBackedFileDelegate.h"
#import "GMDirectoryEntry.h"
#import "GMFinderInfo.h"
#import "GMResourceFork.h"

#import "GMDTrace.h"

NS_ASSUME_NONNULL_BEGIN

#define GM_EXPORT __attribute__((visibility("default")))

// Creates a dtrace-ready string with any newlines removed.
#define DTRACE_STRING(s) \
  ((char *)[s stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String)

// Operation Context
GM_EXPORT NSString * const kGMUserFileSystemContextUserIDKey = @"kGMUserFileSystemContextUserIDKey";
GM_EXPORT NSString * const kGMUserFileSystemContextGroupIDKey = @"kGMUserFileSystemContextGroupIDKey";
GM_EXPORT NSString * const kGMUserFileSystemContextProcessIDKey = @"kGMUserFileSystemContextProcessIDKey";

// Notifications
GM_EXPORT NSString * const kGMUserFileSystemErrorDomain = @"GMUserFileSystemErrorDomain";
GM_EXPORT NSString * const kGMUserFileSystemErrorKey = @"error";
GM_EXPORT NSString * const kGMUserFileSystemMountFailed = @"kGMUserFileSystemMountFailed";
GM_EXPORT NSString * const kGMUserFileSystemDidMount = @"kGMUserFileSystemDidMount";
GM_EXPORT NSString * const kGMUserFileSystemDidUnmount = @"kGMUserFileSystemDidUnmount";

// Deprecated notification key that we still support for backward compatibility
GM_EXPORT NSString * const kGMUserFileSystemMountPathKey = @"mountPath";

// Attribute keys
GM_EXPORT NSString * const kGMUserFileSystemFileFlagsKey = @"kGMUserFileSystemFileFlagsKey";
GM_EXPORT NSString * const kGMUserFileSystemFileAccessDateKey = @"kGMUserFileSystemFileAccessDateKey";
GM_EXPORT NSString * const kGMUserFileSystemFileChangeDateKey = @"kGMUserFileSystemFileChangeDateKey";
GM_EXPORT NSString * const kGMUserFileSystemFileBackupDateKey = @"kGMUserFileSystemFileBackupDateKey";
GM_EXPORT NSString * const kGMUserFileSystemFileSizeInBlocksKey = @"kGMUserFileSystemFileSizeInBlocksKey";
GM_EXPORT NSString * const kGMUserFileSystemFileOptimalIOSizeKey = @"kGMUserFileSystemFileOptimalIOSizeKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsAllocateKey = @"kGMUserFileSystemVolumeSupportsAllocateKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey = @"kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsExchangeDataKey = @"kGMUserFileSystemVolumeSupportsExchangeDataKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsSwapRenamingKey = @"kGMUserFileSystemVolumeSupportsSwapRenamingKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsExclusiveRenamingKey = @"kGMUserFileSystemVolumeSupportsExclusiveRenamingKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsExtendedDatesKey = @"kGMUserFileSystemVolumeSupportsExtendedDatesKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeMaxFilenameLengthKey = @"kGMUserFileSystemVolumeMaxFilenameLengthKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeFileSystemBlockSizeKey = @"kGMUserFileSystemVolumeFileSystemBlockSizeKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsSetVolumeNameKey = @"kGMUserFileSystemVolumeSupportsSetVolumeNameKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeNameKey = @"kGMUserFileSystemVolumeNameKey";
GM_EXPORT NSString * const kGMUserFileSystemVolumeSupportsReadWriteNodeLockingKey = @"kGMUserFileSystemVolumeSupportsReadWriteNodeLockingKey";

// FinderInfo and ResourceFork keys
GM_EXPORT NSString * const kGMUserFileSystemFinderFlagsKey = @"kGMUserFileSystemFinderFlagsKey";
GM_EXPORT NSString * const kGMUserFileSystemFinderExtendedFlagsKey = @"kGMUserFileSystemFinderExtendedFlagsKey";
GM_EXPORT NSString * const kGMUserFileSystemCustomIconDataKey = @"kGMUserFileSystemCustomIconDataKey";
GM_EXPORT NSString * const kGMUserFileSystemWeblocURLKey = @"kGMUserFileSystemWeblocURLKey";

// Used for time conversions to/from tv_nsec.
static const double kNanoSecondsPerSecond = 1000000000.0;

typedef enum {
  // Unable to unmount a dead FUSE files system located at mount point.
  GMUserFileSystem_ERROR_UNMOUNT_DEADFS = 1000,

  // Gave up waiting for system removal of existing dir in /Volumes/x after
  // unmounting a dead FUSE file system.
  GMUserFileSystem_ERROR_UNMOUNT_DEADFS_RMDIR = 1001,

  // The mount point did not exist, and we were unable to mkdir it.
  GMUserFileSystem_ERROR_MOUNT_MKDIR = 1002,

  // fuse_main returned while trying to mount and don't know why.
  GMUserFileSystem_ERROR_MOUNT_FUSE_MAIN_INTERNAL = 1003,
} GMUserFileSystemErrorCode;

typedef enum {
  GMUserFileSystem_NOT_MOUNTED,     // Not mounted.
  GMUserFileSystem_MOUNTING,        // In the process of mounting.
  GMUserFileSystem_INITIALIZING,    // Almost done mounting.
  GMUserFileSystem_MOUNTED,         // Confirmed to be mounted.
  GMUserFileSystem_UNMOUNTING,      // In the process of unmounting.
  GMUserFileSystem_FAILURE,         // Failed state; probably a mount failure.
} GMUserFileSystemStatus;

@interface GMUserFileSystemInternal : NSObject

- (instancetype)initWithDelegate:(nullable id)delegate isThreadSafe:(BOOL)isThreadSafe;

@property (nonatomic, unsafe_unretained, nullable) struct fuse *handle;
@property (nonatomic, copy, nullable) NSString *mountPath;
@property (nonatomic) GMUserFileSystemStatus status;

@property (nonatomic, copy) NSArray<dispatch_source_t> *signalSources;

// Is the delegate thread-safe?
@property (nonatomic, readonly) BOOL isThreadSafe;

// Delegate supports preallocation of files?
@property (nonatomic) BOOL supportsAllocate;

// Delegate supports case sensitive names?
@property (nonatomic) BOOL supportsCaseSensitiveNames;

// Delegate supports exchange data?
@property (nonatomic) BOOL supportsExchangeData;

// Delegate supports exclusive renaming?
@property (nonatomic) BOOL supportsExclusiveRenaming;

// Delegate supports create and backup times?
@property (nonatomic) BOOL supportsExtendedTimes;

// Delegate supports read/write node locking?
@property (nonatomic) BOOL supportsReadWriteNodeLocking;

// Delegate supports setvolname?
@property (nonatomic) BOOL supportsSetVolumeName;

// Delegate supports swap renaming?
@property (nonatomic) BOOL supportsSwapRenaming;

// Is this mounted read-only?
@property (nonatomic, getter=isReadOnly) BOOL readOnly;

@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *defaultAttributes;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *defaultRootAttributes;

// Try to handle FinderInfo/Resource Forks?
@property (nonatomic, readonly) BOOL shouldCheckForResource;

@property (nonatomic, unsafe_unretained, nullable) id delegate;

@end

@implementation GMUserFileSystemInternal

@synthesize isThreadSafe = _isThreadSafe;
@synthesize shouldCheckForResource = _shouldCheckForResource;

- (instancetype)init {
  return [self initWithDelegate:nil isThreadSafe:NO];
}

- (instancetype)initWithDelegate:(nullable id)delegate isThreadSafe:(BOOL)isThreadSafe {
  self = [super init];
  if (self) {
    _status = GMUserFileSystem_NOT_MOUNTED;
    _isThreadSafe = isThreadSafe;
    _supportsAllocate = NO;
    _supportsCaseSensitiveNames = YES;
    _supportsExchangeData = NO;
    _supportsExclusiveRenaming = NO;
    _supportsExtendedTimes = NO;
    _supportsReadWriteNodeLocking = NO;
    _supportsSetVolumeName = NO;
    _supportsSwapRenaming = NO;
    _readOnly = NO;
    [self setDelegate:delegate];
  }
  return self;
}
- (void)dealloc {
  [_mountPath release];
  [_signalSources release];
  [_defaultAttributes release];
  [_defaultRootAttributes release];
  [super dealloc];
}

- (void)setDelegate:(nullable id)delegate {
  _delegate = delegate;
  _shouldCheckForResource =
    [_delegate respondsToSelector:@selector(finderAttributesAtPath:error:)] ||
    [_delegate respondsToSelector:@selector(resourceAttributesAtPath:error:)];

  // Check for deprecated methods.
  SEL deprecatedMethods[] = {
    @selector(contentsOfDirectoryAtPath:error:),
  };
  for (int i = 0; i < sizeof(deprecatedMethods) / sizeof(SEL); ++i) {
    SEL sel = deprecatedMethods[i];
    if ([_delegate respondsToSelector:sel]) {
      NSLog(@"*** WARNING: GMUserFileSystem delegate implements deprecated "
            @"selector: %@", NSStringFromSelector(sel));
    }
  }
}

@end

// Deprecated delegate methods that we still support for backward compatibility
// with previously compiled file systems. This will be actively trimmed as
// new releases occur.
@interface NSObject (GMUserFileSystemDeprecated)

- (nullable NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path
                                                      error:(NSError * _Nullable * _Nonnull)error;

@end

@interface GMUserFileSystem (GMUserFileSystemPrivate)

// The file system for the current thread. Valid only during a FUSE callback.
+ (GMUserFileSystem *)currentFS;

// Convenience method to creates an autoreleased NSError in the
// NSPOSIXErrorDomain. Filesystem errors returned by the delegate must be
// standard posix errno values.
+ (NSError *)errorWithCode:(int)code;

- (void)mount:(NSDictionary<NSString *, id> *)args;
- (void)waitUntilMounted:(NSNumber *)fileDescriptor;

- (void)registerSignalSources;
- (void)deregisterSignalSources;

- (NSDictionary<NSString *, id> *)finderAttributesAtPath:(NSString *)path;
- (NSDictionary<NSString *, id> *)resourceAttributesAtPath:(NSString *)path;

- (BOOL)hasCustomIconAtPath:(NSString *)path;
- (BOOL)isDirectoryIconAtPath:(NSString *)path dirPath:(NSString **)dirPath;
- (NSData *)finderDataForAttributes:(NSDictionary<NSString *, id> *)attributes;
- (NSData *)resourceDataForAttributes:(NSDictionary<NSString *, id> *)attributes;

- (NSDictionary<NSString *, id> *)defaultAttributesOfItemAtPath:(NSString *)path
                                                       userData:userData
                                                          error:(NSError * _Nullable * _Nonnull)error;
- (BOOL)fillStatBuffer:(struct stat *)stbuf
               forPath:(NSString *)path
              userData:(nullable id)userData
                 error:(NSError * _Nullable * _Nonnull)error;
- (BOOL)fillStatfsBuffer:(struct statfs *)stbuf
                 forPath:(NSString *)path
                   error:(NSError * _Nullable * _Nonnull)error;

- (void)fuseInit;
- (void)fuseDestroy;

@end

@implementation GMUserFileSystem

+ (nullable NSDictionary<NSString *, id> *)currentContext {
  struct fuse_context *context = fuse_get_context();
  if (!context) {
    return nil;
  }

  return @{
    kGMUserFileSystemContextUserIDKey: [NSNumber numberWithUnsignedInt:context->uid],
    kGMUserFileSystemContextGroupIDKey: [NSNumber numberWithUnsignedInt:context->gid],
    kGMUserFileSystemContextProcessIDKey: [NSNumber numberWithInt:context->pid]
  };
}

- (instancetype)init {
  return [self initWithDelegate:nil isThreadSafe:NO];
}

- (instancetype)initWithDelegate:(nullable id)delegate isThreadSafe:(BOOL)isThreadSafe {
  self = [super init];
  if (self) {
    internal_ = [[GMUserFileSystemInternal alloc] initWithDelegate:delegate
                                                      isThreadSafe:isThreadSafe];
  }
  return self;
}

- (void)dealloc {
  [internal_ release];
  [super dealloc];
}

- (void)setDelegate:(nullable id)delegate {
  internal_.delegate = delegate;
}
- (nullable id)delegate {
  return internal_.delegate ;
}

- (BOOL)enableAllocate {
  return internal_.supportsAllocate;
}
- (BOOL)enableCaseSensitiveNames {
  return internal_.supportsCaseSensitiveNames;
}
- (BOOL)enableExchangeData {
  return internal_.supportsExchangeData;
}
- (BOOL)enableExclusiveRenaming {
  return internal_.supportsExclusiveRenaming;
}
- (BOOL)enableExtendedTimes {
  return internal_.supportsExtendedTimes;
}
- (BOOL)enableReadWriteNodeLocking {
  return internal_.supportsReadWriteNodeLocking;
}
- (BOOL)enableSetVolumeName {
  return internal_.supportsSetVolumeName;
}
- (BOOL)enableSwapRenaming {
  return internal_.supportsSwapRenaming;
}

- (void)mountAtPath:(NSString *)mountPath
        withOptions:(NSArray<NSString *> *)options {
  [self mountAtPath:mountPath
        withOptions:options
   shouldForeground:YES
    detachNewThread:YES];
}

- (void)mountAtPath:(NSString *)mountPath
        withOptions:(NSArray<NSString *> *)options
   shouldForeground:(BOOL)shouldForeground
    detachNewThread:(BOOL)detachNewThread {
  internal_.mountPath = mountPath;
  BOOL readOnly = NO;
  NSMutableArray<NSString *> *optionsCopy = [NSMutableArray array];
  for (int i = 0; i < options.count; ++i) {
    NSString *option = options[i];
    NSString *optionLowercase = [option lowercaseString];
    if ([optionLowercase compare:@"rdonly"] == NSOrderedSame ||
        [optionLowercase compare:@"ro"] == NSOrderedSame) {
      readOnly = YES;
    }
    [optionsCopy addObject:[[option copy] autorelease]];
  }
  internal_.readOnly = readOnly;

  NSMutableDictionary<NSString *, id> *attributes = [NSMutableDictionary dictionary];
  attributes[NSFilePosixPermissions] = [NSNumber numberWithLong:(readOnly ? 0555 : 0775)];
  attributes[NSFileReferenceCount] = [NSNumber numberWithLong:1];  // 1 means "don't know"
  attributes[NSFileType] = NSFileTypeRegular;
  internal_.defaultAttributes = attributes;

  attributes[NSFileType] = NSFileTypeDirectory;
  internal_.defaultRootAttributes = attributes;

  NSDictionary<NSString *, id> *args = @{
    @"options": optionsCopy,
    @"shouldForeground": [NSNumber numberWithBool:shouldForeground]
  };
  if (detachNewThread) {
    [NSThread detachNewThreadSelector:@selector(mount:)
                             toTarget:self
                           withObject:args];
  } else {
    [self mount:args];
  }
}

- (void)unmount {
  if (internal_.status == GMUserFileSystem_MOUNTED) {
    struct fuse *handle = internal_.handle;
    if (handle) {
      struct fuse_session *session = fuse_get_session(handle);
      struct fuse_chan *channel = fuse_session_next_chan(session, NULL);
      fuse_unmount(NULL, channel);
    }
  }
}

- (BOOL)invalidateItemAtPath:(NSString *)path error:(NSError * _Nullable * _Nonnull)error {
  int ret = -ENOTCONN;

  struct fuse *handle = internal_.handle;
  if (handle) {
    ret = fuse_invalidate_path(handle, path.fileSystemRepresentation);

    // Note: fuse_invalidate_path() may return -ENOENT to indicate that there
    // was no entry to be invalidated, e.g., because the path has not been seen
    // before or has been forgotten. This should not be considered to be an
    // error.
    if (ret == -ENOENT) {
      ret = 0;
    }
  }

  if (ret != 0) {
    *error = [GMUserFileSystem errorWithCode:-ret];
    return NO;
  }

  return YES;
}

+ (NSError *)errorWithCode:(int)code {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

+ (GMUserFileSystem *)currentFS {
  struct fuse_context *context = fuse_get_context();
  assert(context);
  return (GMUserFileSystem *)context->private_data;
}

static const int kMaxWaitForMountTries = 50;
static const int kWaitForMountUSleepInterval = 100000;  // 100 ms

- (void)waitUntilMounted:(NSValue *)handle {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  struct fuse *fuse = (struct fuse *)handle.pointerValue;
  struct fuse_session *se = fuse_get_session(fuse);
  struct fuse_chan *chan = fuse_session_next_chan(se, NULL);

  for (int i = 0; i < kMaxWaitForMountTries; ++i) {
    if (fuse_chan_disk(chan)) {
      internal_.status = GMUserFileSystem_MOUNTED;

      // Successfully mounted, so post notification.
      NSDictionary<NSString *, id> *userInfo = @{
        kGMUserFileSystemMountPathKey: internal_.mountPath
      };
      NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
      [center postNotificationName:kGMUserFileSystemDidMount object:self
                          userInfo:userInfo];
      [pool release];
      return;
    }
    usleep(kWaitForMountUSleepInterval);
  }

  // Tried for a long time and no luck :-(
  // Unmount and report failure?
  [pool release];
}

- (void)fuseInit {
  struct fuse_context *context = fuse_get_context();

  internal_.handle = context->fuse;
  internal_.status = GMUserFileSystem_INITIALIZING;

  NSError *error = nil;
  NSDictionary<NSString *, id> *attribs = [self attributesOfFileSystemForPath:@"/" error:&error];

  if (attribs) {
    NSNumber *supports = nil;

    supports = attribs[kGMUserFileSystemVolumeSupportsAllocateKey];
    if (supports) {
      internal_.supportsAllocate = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey];
    if (supports) {
      internal_.supportsCaseSensitiveNames = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsExchangeDataKey];
    if (supports) {
      internal_.supportsExchangeData = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsSwapRenamingKey];
    if (supports) {
      internal_.supportsSwapRenaming = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsExclusiveRenamingKey];
    if (supports) {
      internal_.supportsExclusiveRenaming = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsExtendedDatesKey];
    if (supports) {
      internal_.supportsExtendedTimes = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsSetVolumeNameKey];
    if (supports) {
      internal_.supportsSetVolumeName = supports.boolValue;
    }

    supports = attribs[kGMUserFileSystemVolumeSupportsReadWriteNodeLockingKey];
    if (supports) {
      internal_.supportsReadWriteNodeLocking = supports.boolValue;
    }
  }

  // The mount point won't actually show up until this winds its way
  // back through the kernel after this routine returns. In order to post
  // the kGMUserFileSystemDidMount notification we start a new thread that will
  // poll until it is mounted.
  [NSThread detachNewThreadSelector:@selector(waitUntilMounted:)
                           toTarget:self
                         withObject:[NSValue valueWithPointer:context->fuse]];
}

- (void)fuseDestroy {
  if ([internal_.delegate respondsToSelector:@selector(willUnmount)]) {
    [internal_.delegate willUnmount];
  }
  internal_.status = GMUserFileSystem_UNMOUNTING;

  NSDictionary<NSString *, id> *userInfo = @{
    kGMUserFileSystemMountPathKey: internal_.mountPath
  };
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  [center postNotificationName:kGMUserFileSystemDidUnmount object:self
                      userInfo:userInfo];
  internal_.status = GMUserFileSystem_NOT_MOUNTED;
}

#pragma mark Finder Info, Resource Forks and HFS headers

- (NSDictionary<NSString *, id> *)finderAttributesAtPath:(NSString *)path {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  UInt16 flags = 0;

  // If a directory icon, we'll make invisible and update the path to parent.
  if ([self isDirectoryIconAtPath:path dirPath:&path]) {
    flags |= kIsInvisible;
  }

  id delegate = internal_.delegate ;
  if ([delegate respondsToSelector:@selector(finderAttributesAtPath:error:)]) {
    NSError *error = nil;
    NSDictionary<NSString *, id> *dict = [delegate finderAttributesAtPath:path error:&error];
    if (dict != nil) {
      if (dict[kGMUserFileSystemCustomIconDataKey]) {
        // They have custom icon data, so make sure the FinderFlags bit is set.
        flags |= kHasCustomIcon;
      }
      if (flags != 0) {
        // May need to update kGMUserFileSystemFinderFlagsKey if different.
        NSNumber *finderFlags = dict[kGMUserFileSystemFinderFlagsKey];
        if (finderFlags != nil) {
          UInt16 tmp = (UInt16)[finderFlags longValue];
          if (flags == tmp) {
            return dict;  // They already have our desired flags.
          }
          flags |= tmp;
        }
        // Doh! We need to create a new dict with the updated flags key.
        NSMutableDictionary<NSString *, id> *newDict =
          [NSMutableDictionary dictionaryWithDictionary:dict];
        newDict[kGMUserFileSystemFinderFlagsKey] = [NSNumber numberWithLong:flags];
        return newDict;
      }
      return dict;
    }
    // Fall through and create dictionary based on flags if necessary.
  }
  if (flags != 0) {
    return @{
      kGMUserFileSystemFinderFlagsKey: [NSNumber numberWithLong:flags]
    };
  }
  return nil;
}

- (NSDictionary<NSString *, id> *)resourceAttributesAtPath:(NSString *)path {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  id delegate = internal_.delegate ;
  if ([delegate respondsToSelector:@selector(resourceAttributesAtPath:error:)]) {
    NSError *error = nil;
    return [delegate resourceAttributesAtPath:path error:&error];
  }
  return nil;
}

- (BOOL)hasCustomIconAtPath:(NSString *)path {
  if ([path isEqualToString:@"/"]) {
    return NO;  // For a volume icon they should use the volicon= option.
  }
  NSDictionary<NSString *, id> *finderAttribs = [self finderAttributesAtPath:path];
  if (finderAttribs) {
    NSNumber *finderFlags =
      finderAttribs[kGMUserFileSystemFinderFlagsKey];
    if (finderFlags) {
      UInt16 flags = (UInt16)[finderFlags longValue];
      return (flags & kHasCustomIcon) == kHasCustomIcon;
    }
  }
  return NO;
}

- (BOOL)isDirectoryIconAtPath:(NSString *)path dirPath:(NSString **)dirPath {
  NSString *name = [path lastPathComponent];
  if ([name isEqualToString:@"Icon\r"]) {
    if (dirPath) {
      *dirPath = [path stringByDeletingLastPathComponent];
    }
    return YES;
  }
  return NO;
}

// If the given attribs dictionary contains any FinderInfo attributes then
// returns NSData for FinderInfo; otherwise returns nil.
- (NSData *)finderDataForAttributes:(NSDictionary<NSString *, id> *)attribs {
  if (!attribs) {
    return nil;
  }

  GMFinderInfo *info = [GMFinderInfo finderInfo];
  BOOL attributeFound = NO;  // Have we found at least one relevant attribute?

  NSNumber *flags = attribs[kGMUserFileSystemFinderFlagsKey];
  if (flags) {
    attributeFound = YES;
    [info setFlags:(UInt16)[flags longValue]];
  }

  NSNumber *extendedFlags =
    attribs[kGMUserFileSystemFinderExtendedFlagsKey];
  if (extendedFlags) {
    attributeFound = YES;
    [info setExtendedFlags:(UInt16)[extendedFlags longValue]];
  }

  NSNumber *typeCode = attribs[NSFileHFSTypeCode];
  if (typeCode) {
    attributeFound = YES;
    [info setTypeCode:(OSType)[typeCode longValue]];
  }

  NSNumber *creatorCode = attribs[NSFileHFSCreatorCode];
  if (creatorCode) {
    attributeFound = YES;
    [info setCreatorCode:(OSType)[creatorCode longValue]];
  }

  return attributeFound ? [info data] : nil;
}

// If the given attribs dictionary contains any ResourceFork attributes then
// returns NSData for the ResourceFork; otherwise returns nil.
- (NSData *)resourceDataForAttributes:(NSDictionary<NSString *, id> *)attribs {
  if (!attribs) {
    return nil;
  }

  GMResourceFork *fork = [GMResourceFork resourceFork];
  BOOL attributeFound = NO;  // Have we found at least one relevant attribute?

  NSData *imageData = attribs[kGMUserFileSystemCustomIconDataKey];
  if (imageData) {
    attributeFound = YES;
    [fork addResourceWithType:'icns'
                        resID:kCustomIconResource // -16455
                         name:nil
                         data:imageData];
  }
  NSURL *url = attribs[kGMUserFileSystemWeblocURLKey];
  if (url) {
    attributeFound = YES;
    NSString *urlString = [url absoluteString];
    NSData *data = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    [fork addResourceWithType:'url '
                        resID:256
                         name:nil
                         data:data];
  }
  return attributeFound ? [fork data] : nil;
}

#pragma mark Internal Stat Operations

- (BOOL)fillStatfsBuffer:(struct statfs *)stbuf
                 forPath:(NSString *)path
                   error:(NSError * _Nullable * _Nonnull)error {
  NSDictionary<NSString *, id> *attributes = [self attributesOfFileSystemForPath:path error:error];
  if (!attributes) {
    return NO;
  }

  // Block size
  NSNumber *blocksize = attributes[kGMUserFileSystemVolumeFileSystemBlockSizeKey];
  assert(blocksize);
  stbuf->f_bsize = (uint32_t)[blocksize unsignedIntValue];
  stbuf->f_iosize = (int32_t)[blocksize intValue];

  // Size in blocks
  NSNumber *size = attributes[NSFileSystemSize];
  assert(size);
  stbuf->f_blocks = (uint64_t)([size unsignedLongLongValue] / stbuf->f_bsize);

  // Number of free / available blocks
  NSNumber *freeSize = attributes[NSFileSystemFreeSize];
  assert(freeSize);
  stbuf->f_bavail = stbuf->f_bfree =
    (uint64_t)([freeSize unsignedLongLongValue] / stbuf->f_bsize);

  // Number of nodes
  NSNumber *numNodes = attributes[NSFileSystemNodes];
  assert(numNodes);
  stbuf->f_files = (uint64_t)[numNodes unsignedLongLongValue];

  // Number of free / available nodes
  NSNumber *freeNodes = attributes[NSFileSystemFreeNodes];
  assert(freeNodes);
  stbuf->f_ffree = (uint64_t)[freeNodes unsignedLongLongValue];

  return YES;
}

- (BOOL)fillStatBuffer:(struct stat *)stbuf
               forPath:(NSString *)path
              userData:(nullable id)userData
                 error:(NSError * _Nullable * _Nonnull)error {
  NSDictionary<NSString *, id> *attributes = [self defaultAttributesOfItemAtPath:path
                                                                        userData:userData
                                                                           error:error];
  if (!attributes) {
    return NO;
  }

  // Inode
  NSNumber *inode = attributes[NSFileSystemFileNumber];
  if (inode) {
    stbuf->st_ino = [inode longLongValue];
  }

  // Permissions (mode)
  NSNumber *perm = attributes[NSFilePosixPermissions];
  stbuf->st_mode = [perm longValue];
  NSString *fileType = attributes[NSFileType];
  if ([fileType isEqualToString:NSFileTypeDirectory]) {
    stbuf->st_mode |= S_IFDIR;
  } else if ([fileType isEqualToString:NSFileTypeRegular]) {
    stbuf->st_mode |= S_IFREG;
  } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
    stbuf->st_mode |= S_IFLNK;
  } else {
    *error = [GMUserFileSystem errorWithCode:EFTYPE];
    return NO;
  }

  // Owner and Group
  // Note that if the owner or group IDs are not specified, the effective
  // user and group IDs for the current process are used as defaults.
  NSNumber *uid = attributes[NSFileOwnerAccountID];
  NSNumber *gid = attributes[NSFileGroupOwnerAccountID];
  stbuf->st_uid = uid ? [uid unsignedIntValue] : geteuid();
  stbuf->st_gid = gid ? [gid unsignedIntValue] : getegid();

  // nlink
  NSNumber *nlink = attributes[NSFileReferenceCount];
  stbuf->st_nlink = [nlink longValue];

  // flags
  NSNumber *flags = attributes[kGMUserFileSystemFileFlagsKey];
  if (flags) {
    stbuf->st_flags = [flags unsignedIntValue];
  } else {
    // Just in case they tried to use NSFileImmutable or NSFileAppendOnly
    NSNumber *immutableFlag = attributes[NSFileImmutable];
    if (immutableFlag && [immutableFlag boolValue]) {
      stbuf->st_flags |= UF_IMMUTABLE;
    }
    NSNumber *appendFlag = attributes[NSFileAppendOnly];
    if (appendFlag && [appendFlag boolValue]) {
      stbuf->st_flags |= UF_APPEND;
    }
  }

  // Note: We default atime, ctime to mtime if it is provided.
  NSDate *mdate = attributes[NSFileModificationDate];
  if (mdate) {
    const double seconds_dp = [mdate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond);
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;

    stbuf->st_mtimespec.tv_sec = t_sec;
    stbuf->st_mtimespec.tv_nsec = t_nsec;
    stbuf->st_atimespec = stbuf->st_mtimespec;  // Default to mtime
    stbuf->st_ctimespec = stbuf->st_mtimespec;  // Default to mtime
  }
  NSDate *adate = attributes[kGMUserFileSystemFileAccessDateKey];
  if (adate) {
    const double seconds_dp = [adate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond);
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
    stbuf->st_atimespec.tv_sec = t_sec;
    stbuf->st_atimespec.tv_nsec = t_nsec;
  }
  NSDate *cdate = attributes[kGMUserFileSystemFileChangeDateKey];
  if (cdate) {
    const double seconds_dp = [cdate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond);
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
    stbuf->st_ctimespec.tv_sec = t_sec;
    stbuf->st_ctimespec.tv_nsec = t_nsec;
  }

#ifdef _DARWIN_USE_64_BIT_INODE
  NSDate *bdate = attributes[NSFileCreationDate];
  if (bdate) {
    const double seconds_dp = [bdate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond);
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
    stbuf->st_birthtimespec.tv_sec = t_sec;
    stbuf->st_birthtimespec.tv_nsec = t_nsec;
  }
#endif

  // File size
  // Note that the actual file size of a directory depends on the internal
  // representation of directories in the particular file system. In general
  // this is not the combined size of the files in that directory.
  NSNumber *size = attributes[NSFileSize];
  if (size) {
    stbuf->st_size = [size longLongValue];
  }

  // Set the number of blocks used so that Finder will display size on disk
  // properly. The man page says that this is in terms of 512 byte blocks.
  NSNumber *blocks = attributes[kGMUserFileSystemFileSizeInBlocksKey];
  if (blocks) {
    stbuf->st_blocks = [blocks longLongValue];
  } else if (stbuf->st_size > 0) {
    stbuf->st_blocks = stbuf->st_size / 512;
    if (stbuf->st_size % 512) {
      ++(stbuf->st_blocks);
    }
  }

  // Optimal file I/O size
  NSNumber *ioSize = attributes[kGMUserFileSystemFileOptimalIOSizeKey];
  if (ioSize) {
    stbuf->st_blksize = [ioSize intValue];
  }

  return YES;
}

#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)path
                   attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes
                        error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSMutableString *traceinfo =
     [NSMutableString stringWithFormat:@"%@ [%@]", path, attributes];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(createDirectoryAtPath:attributes:error:)]) {
    return [internal_.delegate createDirectoryAtPath:path attributes:attributes error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

- (BOOL)createFileAtPath:(NSString *)path
              attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes
                   flags:(int)flags
                userData:(id *)userData
                   error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo = [NSString stringWithFormat:@"%@ [%@]", path, attributes];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(createFileAtPath:attributes:flags:userData:error:)]) {
    return [internal_.delegate createFileAtPath:path
                                       attributes:attributes
                                            flags:flags
                                         userData:userData
                                            error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Removing an Item

- (BOOL)removeDirectoryAtPath:(NSString *)path
                        error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  if ([internal_.delegate respondsToSelector:@selector(removeDirectoryAtPath:error:)]) {
    return [internal_.delegate removeDirectoryAtPath:path error:error];
  }
  return [self removeItemAtPath:path error:error];
}

- (BOOL)removeItemAtPath:(NSString *)path
                   error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  if ([internal_.delegate respondsToSelector:@selector(removeItemAtPath:error:)]) {
    return [internal_.delegate removeItemAtPath:path error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Moving an Item

- (BOOL)moveItemAtPath:(NSString *)source
                toPath:(NSString *)destination
               options:(GMUserFileSystemMoveOption)options
                 error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@ -> %@", source, destination];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(moveItemAtPath:toPath:options:error:)]) {
    return [internal_.delegate moveItemAtPath:source
                                         toPath:destination
                                        options:options
                                          error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Linking an Item

- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo = [NSString stringWithFormat:@"%@ -> %@", path, otherPath];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(linkItemAtPath:toPath:error:)]) {
    return [internal_.delegate linkItemAtPath:path toPath:otherPath error:error];
  }

  *error = [GMUserFileSystem errorWithCode:ENOTSUP];  // Note: error not in man page.
  return NO;
}

#pragma mark Symbolic Links

- (BOOL)createSymbolicLinkAtPath:(NSString *)path
             withDestinationPath:(NSString *)otherPath
                           error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo = [NSString stringWithFormat:@"%@ -> %@", path, otherPath];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(createSymbolicLinkAtPath:withDestinationPath:error:)]) {
    return [internal_.delegate createSymbolicLinkAtPath:path
                                      withDestinationPath:otherPath
                                                    error:error];
  }

  *error = [GMUserFileSystem errorWithCode:ENOTSUP];  // Note: error not in man page.
  return NO;
}

- (nullable NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                                 error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  if ([internal_.delegate respondsToSelector:@selector(destinationOfSymbolicLinkAtPath:error:)]) {
    return [internal_.delegate destinationOfSymbolicLinkAtPath:path error:error];
  }

  *error = [GMUserFileSystem errorWithCode:ENOENT];
  return nil;
}

#pragma mark Directory Contents

- (nullable NSArray<GMDirectoryEntry *> *)contentsOfDirectoryAtPath:(NSString *)path
                                         includingAttributesForKeys:(NSArray<NSFileAttributeKey> *)keys
                                                              error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  NSArray<GMDirectoryEntry *> *contents = nil;
  if ([internal_.delegate respondsToSelector:@selector(contentsOfDirectoryAtPath:includingAttributesForKeys:error:)]) {
    contents = [internal_.delegate contentsOfDirectoryAtPath:path includingAttributesForKeys:keys error:error];
  } else if ([internal_.delegate respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)]) {
    NSArray<NSString *> *names = [internal_.delegate contentsOfDirectoryAtPath:path error:error];
    NSMutableArray<GMDirectoryEntry *> *entries = [NSMutableArray array];
    for (NSString *name in names) {
      NSString *entryPath = [path stringByAppendingPathComponent:name];
      NSError *error = nil;
      NSDictionary<NSString *, id> *attribs = [self defaultAttributesOfItemAtPath:entryPath
                                                                         userData:nil
                                                                            error:&error];
      if (!attribs) {
        continue;
      }
      GMDirectoryEntry *entry = [GMDirectoryEntry directoryEntryWithName:name attributes:attribs];
      [entries addObject:entry];
    }
    contents = entries;
  } else if ([path isEqualToString:@"/"]) {
    contents = @[];  // Give them an empty root directory for free.
  }
  return contents;
}

#pragma mark File Contents

// Note: Only call this if the delegate does indeed support this method.
- (nullable NSData *)contentsAtPath:(NSString *)path {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  id delegate = internal_.delegate ;
  return [delegate contentsAtPath:path];
}

- (BOOL)openFileAtPath:(NSString *)path
                  mode:(int)mode
              userData:(id *)userData
                 error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo = [NSString stringWithFormat:@"%@, mode=0x%x", path, mode];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  id delegate = internal_.delegate ;
  if ([delegate respondsToSelector:@selector(contentsAtPath:)]) {
    NSData *data = [self contentsAtPath:path];
    if (data != nil) {
      *userData = [GMDataBackedFileDelegate fileDelegateWithData:data];
      return YES;
    }
  } else if ([delegate respondsToSelector:@selector(openFileAtPath:mode:userData:error:)]) {
    if ([delegate openFileAtPath:path
                            mode:mode
                        userData:userData
                           error:error]) {
      return YES;  // They handled it.
    }
  }

  // Still unable to open the file; maybe it is an Icon\r or AppleDouble?
  if (internal_.shouldCheckForResource) {
    NSData *data = nil;  // Synthesized data that we provide a file delegate for.

    // Is it an Icon\r file that we handle?
    if ([self isDirectoryIconAtPath:path dirPath:nil]) {
      data = [NSData data];  // The Icon\r file is empty.
    }

    if (data != nil) {
      if ((mode & O_ACCMODE) == O_RDONLY) {
        *userData = [GMDataBackedFileDelegate fileDelegateWithData:data];
      } else {
        NSMutableData *mutableData = [NSMutableData dataWithData:data];
        *userData =
          [GMMutableDataBackedFileDelegate fileDelegateWithData:mutableData];
      }
      return YES;  // Handled by a synthesized file delegate.
    }
  }

  if (!(*error)) {
    *error = [GMUserFileSystem errorWithCode:ENOENT];
  }
  return NO;
}

- (void)releaseFileAtPath:(NSString *)path userData:(nullable id)userData {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p", path, userData];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if (userData != nil &&
      [userData isKindOfClass:[GMDataBackedFileDelegate class]]) {
    return;  // Don't report releaseFileAtPath for internal file.
  }
  if ([internal_.delegate respondsToSelector:@selector(releaseFileAtPath:userData:)]) {
    [internal_.delegate releaseFileAtPath:path userData:userData];
  }
}

- (int)readFileAtPath:(NSString *)path
             userData:(nullable id)userData
               buffer:(char *)buffer
                 size:(size_t)size
               offset:(off_t)offset
                error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p, offset=%lld, size=%lu",
       path, userData, offset, (unsigned long)size];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if (userData != nil &&
      [userData respondsToSelector:@selector(readToBuffer:size:offset:error:)]) {
    return [userData readToBuffer:buffer size:size offset:offset error:error];
  } else if ([internal_.delegate respondsToSelector:@selector(readFileAtPath:userData:buffer:size:offset:error:)]) {
    return [internal_.delegate readFileAtPath:path
                                       userData:userData
                                         buffer:buffer
                                           size:size
                                         offset:offset
                                          error:error];
  }
  *error = [GMUserFileSystem errorWithCode:EACCES];
  return -1;
}

- (int)writeFileAtPath:(NSString *)path
              userData:(nullable id)userData
                buffer:(const char *)buffer
                  size:(size_t)size
                offset:(off_t)offset
                 error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p, offset=%lld, size=%lu",
       path, userData, offset, (unsigned long)size];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if (userData != nil &&
      [userData respondsToSelector:@selector(writeFromBuffer:size:offset:error:)]) {
    return [userData writeFromBuffer:buffer size:size offset:offset error:error];
  } else if ([internal_.delegate respondsToSelector:@selector(writeFileAtPath:userData:buffer:size:offset:error:)]) {
    return [internal_.delegate writeFileAtPath:path
                                        userData:userData
                                          buffer:buffer
                                            size:size
                                          offset:offset
                                           error:error];
  }
  *error = [GMUserFileSystem errorWithCode:EACCES];
  return -1;
}

- (BOOL)truncateFileAtPath:(NSString *)path
                  userData:(id)userData
                    offset:(off_t)offset
                     error:(NSError * _Nullable * _Nonnull)error
                   handled:(BOOL*)handled {
  if (userData != nil &&
      [userData respondsToSelector:@selector(truncateToOffset:error:)]) {
    *handled = YES;
    return [userData truncateToOffset:offset error:error];
  }
  *handled = NO;
  return NO;
}

- (BOOL)supportsAllocateFileAtPath {
  id delegate = internal_.delegate ;
  return [delegate respondsToSelector:@selector(preallocateFileAtPath:userData:options:offset:length:error:)];
}

- (BOOL)allocateFileAtPath:(NSString *)path
                  userData:(id)userData
                   options:(int)options
                    offset:(off_t)offset
                    length:(off_t)length
                     error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p, options=%d, offset=%lld, length=%lld",
       path, userData, options, offset, length];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([self supportsAllocateFileAtPath]) {
    if ((options & PREALLOCATE) == PREALLOCATE) {
      if ([internal_.delegate respondsToSelector:@selector(preallocateFileAtPath:userData:options:offset:length:error:)]) {
        return [internal_.delegate preallocateFileAtPath:path
                                                  userData:userData
                                                   options:options
                                                    offset:offset
                                                    length:length
                                                     error:error];
      }
    }
    *error = [GMUserFileSystem errorWithCode:ENOTSUP];
    return NO;
  }
  *error = [GMUserFileSystem errorWithCode:ENOSYS];
  return NO;
}

- (BOOL)supportsExchangeData {
  id delegate = internal_.delegate ;
  return [delegate respondsToSelector:@selector(exchangeDataOfItemAtPath:withItemAtPath:error:)];
}

- (BOOL)exchangeDataOfItemAtPath:(NSString *)path
                  withItemAtPath:(NSString *)otherPath
                           error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo = [NSString stringWithFormat:@"%@ <-> %@", path, otherPath];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(exchangeDataOfItemAtPath:withItemAtPath:error:)]) {
    return [internal_.delegate exchangeDataOfItemAtPath:path
                                           withItemAtPath:otherPath
                                                    error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOSYS];
  return NO;
}

#pragma mark Getting and Setting Attributes

- (nullable NSDictionary<NSString *, id> *)attributesOfFileSystemForPath:(NSString *)path
                                                                   error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  NSMutableDictionary<NSString *, id> *attributes = [NSMutableDictionary dictionary];

  NSNumber *defaultSize = [NSNumber numberWithLongLong:(2LL * 1024 * 1024 * 1024)];
  attributes[NSFileSystemSize] = defaultSize;
  attributes[NSFileSystemFreeSize] = defaultSize;
  attributes[NSFileSystemNodes] = defaultSize;
  attributes[NSFileSystemFreeNodes] = defaultSize;
  attributes[kGMUserFileSystemVolumeMaxFilenameLengthKey] = [NSNumber numberWithInt:255];
  attributes[kGMUserFileSystemVolumeFileSystemBlockSizeKey] = [NSNumber numberWithInt:4096];

  NSNumber *supports = nil;

  supports = [NSNumber numberWithBool:[self supportsExchangeData]];
  attributes[kGMUserFileSystemVolumeSupportsExchangeDataKey] = supports;

  supports = [NSNumber numberWithBool:[self supportsAllocateFileAtPath]];
  attributes[kGMUserFileSystemVolumeSupportsAllocateKey] = supports;

  // The delegate can override any of the above defaults by implementing the
  // attributesOfFileSystemForPath selector and returning a custom dictionary.
  if ([internal_.delegate respondsToSelector:@selector(attributesOfFileSystemForPath:error:)]) {
    NSDictionary<NSString *, id> *customAttribs =
      [internal_.delegate attributesOfFileSystemForPath:path error:error];
    if (!customAttribs) {
      if (!(*error)) {
        *error = [GMUserFileSystem errorWithCode:ENODEV];
      }
      return nil;
    }
    [attributes addEntriesFromDictionary:customAttribs];
  }
  return attributes;
}

- (BOOL)setAttributes:(NSDictionary<NSString *, id> *)attributes
   ofFileSystemAtPath:(NSString *)path
                error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, attributes=%@", path, attributes];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if ([internal_.delegate respondsToSelector:@selector(setAttributes:ofFileSystemAtPath:error:)]) {
    return [internal_.delegate setAttributes:attributes ofFileSystemAtPath:path error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOSYS];
  return NO;
}

- (BOOL)supportsAttributesOfItemAtPath {
  id delegate = internal_.delegate ;
  return [delegate respondsToSelector:@selector(attributesOfItemAtPath:userData:error:)];
}

- (nullable NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path
                                                                 userData:userData
                                                                    error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p", path, userData];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  id delegate = internal_.delegate ;
  if ([delegate respondsToSelector:@selector(attributesOfItemAtPath:userData:error:)]) {
    return [delegate attributesOfItemAtPath:path userData:userData error:error];
  }
  return nil;
}

// Get attributesOfItemAtPath from the delegate with default values.
- (NSDictionary<NSFileAttributeKey, id> *)defaultAttributesOfItemAtPath:(NSString *)path
                                                               userData:userData
                                                                  error:(NSError * _Nullable * _Nonnull)error {
  id delegate = internal_.delegate ;
  BOOL isDirectoryIcon = NO;

  // The delegate can override any of the defaults by implementing the
  // attributesOfItemAtPath: selector and returning a custom dictionary.
  NSDictionary<NSString *, id> *attributes = nil;
  BOOL supportsAttributesSelector = [self supportsAttributesOfItemAtPath];
  if (supportsAttributesSelector) {
    attributes = [self attributesOfItemAtPath:path
                                     userData:userData
                                        error:error];
  }

  // Maybe this is the root directory?  If so, we'll claim it always exists.
  if (!attributes && [path isEqualToString:@"/"]) {
    // The root directory always exists.
    return internal_.defaultRootAttributes;
  }

  // Maybe check to see if this is a special file that we should handle. If they
  // wanted to handle it, then they would have given us back customAttribs.
  if (!attributes && internal_.shouldCheckForResource) {
    // If the maybe-fixed-up path is a directoryIcon, we'll modify the path to
    // refer to the parent directory and note that we are a directory icon.
    isDirectoryIcon = [self isDirectoryIconAtPath:path dirPath:&path];

    // Maybe we'll try again to get custom attribs on the real path.
    if (supportsAttributesSelector && isDirectoryIcon) {
      attributes = [self attributesOfItemAtPath:path
                                       userData:userData
                                          error:error];
    }
  }

  NSMutableDictionary<NSString *, id> *mutableAttributes = nil;

  if (attributes) {
    NSDictionary<NSString *, id> *defaultAttributes = internal_.defaultAttributes;
    NSArray<NSString *> *keys = defaultAttributes.allKeys;
    for (int i = 0; i < keys.count; i++) {
      NSString *key = keys[i];
      if (!attributes[key]) {
        if (!mutableAttributes) {
          mutableAttributes = [[attributes mutableCopy] autorelease];
          attributes = mutableAttributes;
        }
        mutableAttributes[key] = defaultAttributes[key];
      }
    }
  } else if (supportsAttributesSelector) {
    // They explicitly support attributesOfItemAtPath: and returned nil.
    if (error && !(*error)) {
      *error = [GMUserFileSystem errorWithCode:ENOENT];
    }
    return nil;
  }

  // If this is a directory Icon\r then it is an empty file and we're done.
  if (isDirectoryIcon) {
    if ([self hasCustomIconAtPath:path]) {
      if (!mutableAttributes) {
        mutableAttributes = [[attributes mutableCopy] autorelease];
        attributes = mutableAttributes;
      }
      mutableAttributes[NSFileType] = NSFileTypeRegular;
      mutableAttributes[NSFileSize] = [NSNumber numberWithLongLong:0];
      return attributes;
    }
    *error = [GMUserFileSystem errorWithCode:ENOENT];
    return nil;
  }

  // If they don't supply a size and it is a file then we try to compute it.
  if (!attributes[NSFileSize] &&
      ![attributes[NSFileType] isEqualToString:NSFileTypeDirectory] &&
      [delegate respondsToSelector:@selector(contentsAtPath:)]) {
    NSData *data = [self contentsAtPath:path];
    if (data == nil) {
      *error = [GMUserFileSystem errorWithCode:ENOENT];
      return nil;
    }
    if (!mutableAttributes) {
      mutableAttributes = [[attributes mutableCopy] autorelease];
      attributes = mutableAttributes;
    }
    mutableAttributes[NSFileSize] = [NSNumber numberWithLongLong:data.length];
  }

  return attributes;
}

- (NSDictionary<NSString *, id> *)extendedTimesOfItemAtPath:(NSString *)path
                                                   userData:(nullable id)userData
                                                      error:(NSError * _Nullable * _Nonnull)error {
  if (![self supportsAttributesOfItemAtPath]) {
    *error = [GMUserFileSystem errorWithCode:ENOSYS];
    return nil;
  }
  return [self attributesOfItemAtPath:path
                             userData:userData
                                error:error];
}

- (BOOL)setAttributes:(NSDictionary<NSFileAttributeKey, id> *)attributes
         ofItemAtPath:(NSString *)path
             userData:(nullable id)userData
                error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p, attributes=%@",
       path, userData, attributes];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  if (attributes[NSFileSize]) {
    BOOL handled = NO;  // Did they have a delegate method that handles truncation?
    NSNumber *offsetNumber = attributes[NSFileSize];
    off_t offset = [offsetNumber longLongValue];
    BOOL ret = [self truncateFileAtPath:path
                               userData:userData
                                 offset:offset
                                  error:error
                                handled:&handled];
    if (handled && (!ret || attributes.count == 1)) {
      // Either the truncate call failed, or we only had NSFileSize, so we are done.
      return ret;
    }
  }

  if ([internal_.delegate respondsToSelector:@selector(setAttributes:ofItemAtPath:userData:error:)]) {
    return [internal_.delegate setAttributes:attributes ofItemAtPath:path userData:userData error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENODEV];
  return NO;
}

#pragma mark Extended Attributes

- (nullable NSArray<NSString *> *)extendedAttributesOfItemAtPath:path
                                                           error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  if ([internal_.delegate respondsToSelector:@selector(extendedAttributesOfItemAtPath:error:)]) {
    return [internal_.delegate extendedAttributesOfItemAtPath:path error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOTSUP];
  return nil;
}

- (nullable NSData *)valueOfExtendedAttribute:(NSString *)name
                                 ofItemAtPath:(NSString *)path
                                     position:(off_t)position
                                        error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, name=%@, position=%lld", path, name, position];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  id delegate = internal_.delegate ;
  NSData *data = nil;
  BOOL xattrSupported = NO;
  if ([delegate respondsToSelector:@selector(valueOfExtendedAttribute:ofItemAtPath:position:error:)]) {
    xattrSupported = YES;
    data = [delegate valueOfExtendedAttribute:name
                                 ofItemAtPath:path
                                     position:position
                                        error:error];
  }

  if (!data && internal_.shouldCheckForResource) {
    if ([name isEqualToString:@"com.apple.FinderInfo"]) {
      NSDictionary<NSString *, id> *finderAttributes = [self finderAttributesAtPath:path];
      data = [self finderDataForAttributes:finderAttributes];
    } else if ([name isEqualToString:@"com.apple.ResourceFork"]) {
      [self isDirectoryIconAtPath:path dirPath:&path];  // Maybe update path.
      NSDictionary<NSString *, id> *attributes = [self resourceAttributesAtPath:path];
      data = [self resourceDataForAttributes:attributes];
    }
    if (data != nil && position > 0) {
      // We have all the data, but they are only requesting a subrange.
      size_t length = [data length];
      if (position > length) {
        *error = [GMUserFileSystem errorWithCode:ERANGE];
        return nil;
      }
      data = [data subdataWithRange:NSMakeRange(position, length - position)];
    }
  }
  if (data == nil && error && !(*error)) {
    *error = [GMUserFileSystem errorWithCode:xattrSupported ? ENOATTR : ENOTSUP];
  }
  return data;
}

- (BOOL)setExtendedAttribute:(NSString *)name
                ofItemAtPath:(NSString *)path
                       value:(NSData *)value
                    position:(off_t)position
                     options:(int)options
                       error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, name=%@, position=%lld, options=0x%x",
       path, name, position, options];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  id delegate = internal_.delegate ;
  if ([delegate respondsToSelector:@selector(setExtendedAttribute:ofItemAtPath:value:position:options:error:)]) {
    return [delegate setExtendedAttribute:name
                             ofItemAtPath:path
                                    value:value
                                 position:position
                                  options:options
                                    error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOTSUP];
  return NO;
}

- (BOOL)removeExtendedAttribute:(NSString *)name
                   ofItemAtPath:(NSString *)path
                          error:(NSError * _Nullable * _Nonnull)error {
  if (MACFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString *traceinfo =
      [NSString stringWithFormat:@"%@, name=%@", path, name];
    MACFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }

  id delegate = internal_.delegate ;
  if ([delegate respondsToSelector:@selector(removeExtendedAttribute:ofItemAtPath:error:)]) {
    return [delegate removeExtendedAttribute:name
                                ofItemAtPath:path
                                       error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOTSUP];
  return NO;
}

#pragma mark FUSE Operations

#define SET_CAPABILITY(conn, flag, enable)                                \
  do {                                                                    \
    if (enable) {                                                         \
      (conn)->want |= (flag);                                             \
    } else {                                                              \
      (conn)->want &= ~(flag);                                            \
    }                                                                     \
  } while (0)

#define MAYBE_USE_ERROR(var, error)                                       \
  if ((error) != nil &&                                                   \
      [[(error) domain] isEqualToString:NSPOSIXErrorDomain]) {            \
    int code = (int)[(error) code];                                       \
    if (code != 0) {                                                      \
      (var) = -code;                                                      \
    }                                                                     \
  }

static void *fusefm_init(struct fuse_conn_info *conn) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  GMUserFileSystem *fs = [GMUserFileSystem currentFS];
  [fs retain];
  @try {
    [fs fuseInit];
  }
  @catch (id exception) { }

  SET_CAPABILITY(conn, FUSE_CAP_ALLOCATE, [fs enableAllocate]);
  SET_CAPABILITY(conn, FUSE_CAP_CASE_INSENSITIVE, ![fs enableCaseSensitiveNames]);
  SET_CAPABILITY(conn, FUSE_CAP_EXCHANGE_DATA, [fs enableExchangeData]);
  SET_CAPABILITY(conn, FUSE_CAP_RENAME_EXCL, [fs enableExclusiveRenaming]);
  SET_CAPABILITY(conn, FUSE_CAP_XTIMES, [fs enableExtendedTimes]);
  SET_CAPABILITY(conn, FUSE_CAP_NODE_RWLOCK, [fs enableReadWriteNodeLocking]);
  SET_CAPABILITY(conn, FUSE_CAP_VOL_RENAME, [fs enableSetVolumeName]);
  SET_CAPABILITY(conn, FUSE_CAP_RENAME_SWAP, [fs enableSwapRenaming]);

  [pool release];
  return fs;
}

static void fusefm_destroy(void *private_data) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  GMUserFileSystem *fs = (GMUserFileSystem *)private_data;
  @try {
    [fs fuseDestroy];
  }
  @catch (id exception) { }
  [fs release];
  [pool release];
}

static int fusefm_mkdir(const char *path, mode_t mode) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError *error = nil;
    unsigned long perm = mode & ALLPERMS;
    NSDictionary<NSString *, id> *attribs = @{
      NSFilePosixPermissions: [NSNumber numberWithLong:perm]
    };
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs createDirectoryAtPath:[NSString stringWithUTF8String:path]
                       attributes:attribs
                            error:&error]) {
      ret = 0;  // Success!
    } else {
      if (error != nil) {
        ret = -(int)[error code];
      }
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError *error = nil;
    id userData = nil;
    unsigned long perms = mode & ALLPERMS;
    NSDictionary<NSString *, id> *attribs = @{
      NSFilePosixPermissions: [NSNumber numberWithUnsignedLong:perms]
    };
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs createFileAtPath:[NSString stringWithUTF8String:path]
                  attributes:attribs
                       flags:fi->flags
                    userData:&userData
                       error:&error]) {
      ret = 0;
      if (userData != nil) {
        [userData retain];
        fi->fh = (uintptr_t)userData;
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_rmdir(const char *path) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs removeDirectoryAtPath:[NSString stringWithUTF8String:path]
                            error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_unlink(const char *path) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs removeItemAtPath:[NSString stringWithUTF8String:path]
                       error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_renamex(const char *path1, const char *path2,
                          unsigned int flags) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];

    GMUserFileSystemMoveOption options = 0;
    if (flags & RENAME_SWAP) {
      options |= GMUserFileSystemMoveOptionSwap;
    }
    if (flags & RENAME_EXCL) {
      options |= GMUserFileSystemMoveOptionExclusive;
    }

    if ([fs moveItemAtPath:[NSString stringWithUTF8String:path1]
                    toPath:[NSString stringWithUTF8String:path2]
                   options:options
                     error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_rename(const char *path1, const char *path2) {
  return fusefm_renamex(path1, path2, 0);
}

static int fusefm_link(const char *path1, const char *path2) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs linkItemAtPath:[NSString stringWithUTF8String:path1]
                    toPath:[NSString stringWithUTF8String:path2]
                     error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_symlink(const char *path1, const char *path2) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs createSymbolicLinkAtPath:[NSString stringWithUTF8String:path2]
                 withDestinationPath:[NSString stringWithUTF8String:path1]
                       error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_readlink(const char *path, char *buf, size_t size)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSString *linkPath = [NSString stringWithUTF8String:path];
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    NSString *pathContent = [fs destinationOfSymbolicLinkAtPath:linkPath
                                                          error:&error];
    if (pathContent != nil) {
      ret = 0;
      [pathContent getFileSystemRepresentation:buf maxLength:size];
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                          off_t offset, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    NSString *dirPath = [NSString stringWithUTF8String:path];

    NSArray<GMDirectoryEntry *> *contents = [fs contentsOfDirectoryAtPath:dirPath
                                               includingAttributesForKeys:@[NSFileType]
                                                                    error:&error];
    if (contents) {
      struct stat stbuf;
      ret = 0;

      memset(&stbuf, 0, sizeof(struct stat));
      stbuf.st_mode = DTTOIF(DT_DIR);
      filler(buf, ".", &stbuf, 0);
      filler(buf, "..", &stbuf, 0);

      for (int i = 0, count = (int)contents.count; i < count; i++) {
        GMDirectoryEntry *entry = contents[i];

        NSString *fileType = entry.attributes[NSFileType];
        if ([fileType isEqualToString:NSFileTypeDirectory]) {
          stbuf.st_mode = S_IFDIR;
        } else if ([fileType isEqualToString:NSFileTypeRegular]) {
          stbuf.st_mode = S_IFREG;
        } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
          stbuf.st_mode = S_IFLNK;
        } else {
          continue;
        }

        filler(buf, entry.name.UTF8String, &stbuf, 0);
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_open(const char *path, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;  // TODO: Default to 0 (success) since a file-system does
                      // not necessarily need to implement open?

  @try {
    id userData = nil;
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs openFileAtPath:[NSString stringWithUTF8String:path]
                      mode:fi->flags
                  userData:&userData
                     error:&error]) {
      ret = 0;
      if (userData != nil) {
        [userData retain];
        fi->fh = (uintptr_t)userData;
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_release(const char *path, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @try {
    id userData = (id)(uintptr_t)fi->fh;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    [fs releaseFileAtPath:[NSString stringWithUTF8String:path] userData:userData];
    if (userData) {
      [userData release];
    }
  }
  @catch (id exception) { }
  [pool release];
  return 0;
}

static int fusefm_read(const char *path, char *buf, size_t size, off_t offset,
                       struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EIO;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    ret = [fs readFileAtPath:[NSString stringWithUTF8String:path]
                    userData:(id)(uintptr_t)fi->fh
                      buffer:buf
                        size:size
                      offset:offset
                       error:&error];
    MAYBE_USE_ERROR(ret, error);
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_write(const char *path, const char *buf, size_t size,
                        off_t offset, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EIO;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    ret = [fs writeFileAtPath:[NSString stringWithUTF8String:path]
                     userData:(id)(uintptr_t)fi->fh
                       buffer:buf
                         size:size
                       offset:offset
                        error:&error];
    MAYBE_USE_ERROR(ret, error);
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_fsync(const char *path, int isdatasync,
                        struct fuse_file_info *fi) {
  // TODO: Support fsync?
  return 0;
}

static int fusefm_fallocate(const char *path, int mode, off_t offset,
                            off_t length, struct fuse_file_info *fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOSYS;
  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs allocateFileAtPath:[NSString stringWithUTF8String:path]
                      userData:(fi ? (id)(uintptr_t)fi->fh : nil)
                       options:mode
                        offset:offset
                        length:length
                         error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_exchange(const char *p1, const char *p2, unsigned long opts) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOSYS;
  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs exchangeDataOfItemAtPath:[NSString stringWithUTF8String:p1]
                      withItemAtPath:[NSString stringWithUTF8String:p2]
                               error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_statfs_x(const char *path, struct statfs *stbuf) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(stbuf, 0, sizeof(struct statfs));
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs fillStatfsBuffer:stbuf
                     forPath:[NSString stringWithUTF8String:path]
                       error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_setvolname(const char *name) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOSYS;
  @try {
    NSError *error = nil;
    NSDictionary<NSString *, id> *attribs = @{
      kGMUserFileSystemVolumeNameKey: [NSString stringWithUTF8String:name]
    };
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs setAttributes:attribs ofFileSystemAtPath:@"/" error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_fgetattr(const char *path, struct stat *stbuf,
                           struct fuse_file_info * _Nullable fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(stbuf, 0, sizeof(struct stat));
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    id userData = fi ? (id)(uintptr_t)fi->fh : nil;
    if ([fs fillStatBuffer:stbuf
                   forPath:[NSString stringWithUTF8String:path]
                  userData:userData
                     error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_getattr(const char *path, struct stat *stbuf) {
  return fusefm_fgetattr(path, stbuf, NULL);
}

static int fusefm_getxtimes(const char *path, struct timespec *bkuptime,
                            struct timespec *crtime) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    NSDictionary<NSString *, id> *attribs =
      [fs extendedTimesOfItemAtPath:[NSString stringWithUTF8String:path]
                           userData:nil  // TODO: Maybe this should support FH?
                              error:&error];
    if (attribs) {
      ret = 0;
      NSDate *creationDate = attribs[NSFileCreationDate];
      if (creationDate) {
        const double seconds_dp = [creationDate timeIntervalSince1970];
        const time_t t_sec = (time_t) seconds_dp;
        const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond);
        const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
        crtime->tv_sec = t_sec;
        crtime->tv_nsec = t_nsec;
      } else {
        memset(crtime, 0, sizeof(struct timespec));
      }
      NSDate *backupDate = attribs[kGMUserFileSystemFileBackupDateKey];
      if (backupDate) {
        const double seconds_dp = [backupDate timeIntervalSince1970];
        const time_t t_sec = (time_t) seconds_dp;
        const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond);
        const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
        bkuptime->tv_sec = t_sec;
        bkuptime->tv_nsec = t_nsec;
      } else {
        memset(bkuptime, 0, sizeof(struct timespec));
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static NSDate *dateWithTimespec(const struct timespec *spec) {
  const NSTimeInterval time_ns = spec->tv_nsec;
  const NSTimeInterval time_sec = spec->tv_sec + (time_ns / kNanoSecondsPerSecond);
  return [NSDate dateWithTimeIntervalSince1970:time_sec];
}

static NSDictionary<NSString *, id> *dictionaryWithAttributes(const struct setattr_x *attrs) {
  NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];
  if (SETATTR_WANTS_MODE(attrs)) {
    unsigned long perm = attrs->mode & ALLPERMS;
    dict[NSFilePosixPermissions] = [NSNumber numberWithLong:perm];
  }
  if (SETATTR_WANTS_UID(attrs)) {
    dict[NSFileOwnerAccountID] = [NSNumber numberWithLong:attrs->uid];
  }
  if (SETATTR_WANTS_GID(attrs)) {
    dict[NSFileGroupOwnerAccountID] = [NSNumber numberWithLong:attrs->gid];
  }
  if (SETATTR_WANTS_SIZE(attrs)) {
    dict[NSFileSize] = [NSNumber numberWithLongLong:attrs->size];
  }
  if (SETATTR_WANTS_ACCTIME(attrs)) {
    dict[kGMUserFileSystemFileAccessDateKey] = dateWithTimespec(&(attrs->acctime));
  }
  if (SETATTR_WANTS_MODTIME(attrs)) {
    dict[NSFileModificationDate] = dateWithTimespec(&(attrs->modtime));
  }
  if (SETATTR_WANTS_CRTIME(attrs)) {
    dict[NSFileCreationDate] = dateWithTimespec(&(attrs->crtime));
  }
  if (SETATTR_WANTS_CHGTIME(attrs)) {
    dict[kGMUserFileSystemFileChangeDateKey] = dateWithTimespec(&(attrs->chgtime));
  }
  if (SETATTR_WANTS_BKUPTIME(attrs)) {
    dict[kGMUserFileSystemFileBackupDateKey] = dateWithTimespec(&(attrs->bkuptime));
  }
  if (SETATTR_WANTS_FLAGS(attrs)) {
    dict[kGMUserFileSystemFileFlagsKey] = [NSNumber numberWithLong:attrs->flags];
  }
  return dict;
}

static int fusefm_fsetattr_x(const char *path, struct setattr_x *attrs,
                             struct fuse_file_info * _Nullable fi) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // Note: Return success by default.

  @try {
    NSError *error = nil;
    NSDictionary<NSString *, id> *attribs = dictionaryWithAttributes(attrs);
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs setAttributes:attribs
             ofItemAtPath:[NSString stringWithUTF8String:path]
                 userData:(fi ? (id)(uintptr_t)fi->fh : nil)
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_setattr_x(const char *path, struct setattr_x *attrs) {
  return fusefm_fsetattr_x(path, attrs, NULL);
}

static int fusefm_listxattr(const char *path, char *list, size_t size)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOTSUP;
  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    NSArray<NSString *> *attributeNames =
      [fs extendedAttributesOfItemAtPath:[NSString stringWithUTF8String:path]
                                   error:&error];
    if (attributeNames != nil) {
      char zero = 0;
      NSMutableData *data = [NSMutableData dataWithCapacity:size];
      for (int i = 0, count = (int)attributeNames.count; i < count; i++) {
        [data appendData:[attributeNames[i] dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendBytes:&zero length:1];
      }
      ret = (int)[data length];  // default to returning size of buffer.
      if (list) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:list length:size];
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_getxattr(const char *path, const char *name, char *value,
                           size_t size, uint32_t position) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOATTR;

  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    NSData *data = [fs valueOfExtendedAttribute:[NSString stringWithUTF8String:name]
                                   ofItemAtPath:[NSString stringWithUTF8String:path]
                                       position:position
                                          error:&error];
    if (data != nil) {
      ret = (int)[data length];  // default to returning size of buffer.
      if (value) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:value length:size];
        ret = (int)size;  // bytes read
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_setxattr(const char *path, const char *name, const char *value,
                           size_t size, int flags, uint32_t position) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -EPERM;
  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs setExtendedAttribute:[NSString stringWithUTF8String:name]
                    ofItemAtPath:[NSString stringWithUTF8String:path]
                           value:[NSData dataWithBytes:value length:size]
                        position:position
                         options:flags
                           error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_removexattr(const char *path, const char *name) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOATTR;
  @try {
    NSError *error = nil;
    GMUserFileSystem *fs = [GMUserFileSystem currentFS];
    if ([fs removeExtendedAttribute:[NSString stringWithUTF8String:name]
                    ofItemAtPath:[NSString stringWithUTF8String:path]
                           error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

#undef MAYBE_USE_ERROR

static struct fuse_operations fusefm_oper = {
  .init = fusefm_init,
  .destroy = fusefm_destroy,

  // Creating an Item
  .mkdir = fusefm_mkdir,
  .create = fusefm_create,

  // Removing an Item
  .rmdir = fusefm_rmdir,
  .unlink = fusefm_unlink,

  // Moving an Item
  .rename = fusefm_rename,
  .renamex = fusefm_renamex,

  // Linking an Item
  .link = fusefm_link,

  // Symbolic Links
  .symlink = fusefm_symlink,
  .readlink = fusefm_readlink,

  // Directory Contents
  .readdir = fusefm_readdir,

  // File Contents
  .open	= fusefm_open,
  .release = fusefm_release,
  .read	= fusefm_read,
  .write = fusefm_write,
  .fsync = fusefm_fsync,
  .fallocate = fusefm_fallocate,
  .exchange = fusefm_exchange,

  // Getting and Setting Attributes
  .statfs_x = fusefm_statfs_x,
  .setvolname = fusefm_setvolname,
  .getattr = fusefm_getattr,
  .fgetattr = fusefm_fgetattr,
  .getxtimes = fusefm_getxtimes,
  .setattr_x = fusefm_setattr_x,
  .fsetattr_x = fusefm_fsetattr_x,

  // Extended Attributes
  .listxattr = fusefm_listxattr,
  .getxattr = fusefm_getxattr,
  .setxattr = fusefm_setxattr,
  .removexattr = fusefm_removexattr,
};

#pragma mark Internal Mount

- (void)registerSignalSources {
  dispatch_queue_t queue =
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

  NSMutableArray<dispatch_source_t> *signalSources =
    [[NSMutableArray alloc] init];

  for (NSNumber *signal in @[@SIGHUP, @SIGINT, @SIGTERM]) {
    dispatch_source_t signalSource =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,
                             signal.unsignedIntValue, 0, queue);
    if (!signalSource) {
      continue;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_IGN;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    sigaction(signal.unsignedIntValue, &sa, NULL);

    __weak GMUserFileSystem *weakSelf = self;
    dispatch_source_set_event_handler(signalSource, ^{
      [weakSelf unmount];
    });
    dispatch_resume(signalSource);

    [signalSources addObject:signalSource];
    dispatch_release(signalSource);
  }

  internal_.signalSources = signalSources;
  [signalSources release];
}

- (void)deregisterSignalSources {
  internal_.signalSources = @[];
}

static struct fuse * _Nullable fusefm_setup(int argc, char * _Nonnull argv[],
                                            const struct fuse_operations *op,
                                            char **mountpoint,
                                            int *multithreaded,
                                            struct fuse_chan **ch,
                                            GMUserFileSystem *fs) {
  struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
  struct fuse *fuse;
  int foreground;
  int res;

  res = fuse_parse_cmdline(&args, mountpoint, multithreaded, &foreground);
  if (res == -1)
    return NULL;

  if (!*mountpoint) {
    fprintf(stderr, "fuse: no mount point\n");
    return NULL;
  }

  *ch = fuse_mount(*mountpoint, &args);
  if (!ch) {
    fuse_opt_free_args(&args);
    goto err_free;
  }

  fuse = fuse_new(*ch, &args, op, sizeof(*op), fs);
  fuse_opt_free_args(&args);
  if (fuse == NULL)
    goto err_unmount;

  res = fuse_daemonize(foreground);
  if (res == -1)
    goto err_unmount;

  [fs registerSignalSources];

  return fuse;

err_unmount:
  fuse_unmount(NULL, *ch);
  if (fuse)
    fuse_destroy(fuse);
err_free:
  free(*mountpoint);
  return NULL;
}

static int fusefm_main(int argc, char * _Nonnull argv[],
                       const struct fuse_operations *op, GMUserFileSystem *fs)
{
  struct fuse *fuse;

  char *mountpoint;
  int multithreaded;
  struct fuse_chan *ch;

  int res;

  fuse = fusefm_setup(argc, argv, op, &mountpoint, &multithreaded, &ch, fs);
  if (!fuse)
    return 1;

  if (multithreaded == FUSE_LOOP_SINGLE_THREADED)
    res = fuse_loop(fuse);
  else if (multithreaded == FUSE_LOOP_MULTI_THREADED)
    res = fuse_loop_mt(fuse);
  else if (multithreaded == FUSE_LOOP_DISPATCH)
    res = fuse_loop_dispatch(fuse);
  else
    return 1;

  [fs deregisterSignalSources];

  fuse_unmount(NULL, ch);
  fuse_destroy(fuse);
  free(mountpoint);

  if (res == -1)
    return 1;
  else
    return 0;
}

- (void)postMountError:(NSError *)error {
  assert(internal_.status == GMUserFileSystem_MOUNTING);
  internal_.status = GMUserFileSystem_FAILURE;

  NSDictionary<NSString *, id> *userInfo = @{
    kGMUserFileSystemMountPathKey: internal_.mountPath,
    kGMUserFileSystemErrorKey: error
  };
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  [center postNotificationName:kGMUserFileSystemMountFailed object:self
                      userInfo:userInfo];
}

- (void)mount:(NSDictionary<NSString *, id> *)args {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  assert(internal_.status == GMUserFileSystem_NOT_MOUNTED);
  internal_.status = GMUserFileSystem_MOUNTING;

  NSArray<NSString *> *options = args[@"options"];
  BOOL isThreadSafe = internal_.isThreadSafe;
  BOOL shouldForeground = [args[@"shouldForeground"] boolValue];

  // Maybe there is a dead FUSE file system stuck on our mount point?
  struct statfs statfs_buf;
  memset(&statfs_buf, 0, sizeof(statfs_buf));
  int ret = statfs(internal_.mountPath.UTF8String, &statfs_buf);
  if (ret == 0) {
    if (statfs_buf.f_fssubtype == (short)(-1)) {
      // We use a special indicator value from FUSE in the f_fssubtype field to
      // indicate that the currently mounted filesystem is dead. It probably
      // crashed and was never unmounted.
      ret = unmount(internal_.mountPath.UTF8String, 0);
      if (ret != 0) {
        NSString *description = @"Unable to unmount an existing 'dead' filesystem.";
        NSDictionary<NSErrorUserInfoKey, id> *userInfo = @{
          NSLocalizedDescriptionKey: description,
          NSUnderlyingErrorKey: [GMUserFileSystem errorWithCode:errno]
        };
        NSError *error = [NSError errorWithDomain:kGMUserFileSystemErrorDomain
                                             code:GMUserFileSystem_ERROR_UNMOUNT_DEADFS
                                         userInfo:userInfo];
        [self postMountError:error];
        [pool release];
        return;
      }
      if ([internal_.mountPath hasPrefix:@"/Volumes/"]) {
        // Directories for mounts in @"/Volumes/..." are removed automatically
        // when an unmount occurs. This is an asynchronous process, so we need
        // to wait until the directory is removed before proceeding. Otherwise,
        // it may be removed after we try to create the mount directory and the
        // mount attempt will fail.
        BOOL isDirectoryRemoved = NO;
        static const int kWaitForDeadFSTimeoutSeconds = 5;
        struct stat stat_buf;
        for (int i = 0; i < 2 * kWaitForDeadFSTimeoutSeconds; ++i) {
          usleep(500000);  // .5 seconds
          ret = stat(internal_.mountPath.UTF8String, &stat_buf);
          if (ret != 0 && errno == ENOENT) {
            isDirectoryRemoved = YES;
            break;
          }
        }
        if (!isDirectoryRemoved) {
          NSString *description =
            @"Gave up waiting for directory under /Volumes to be removed after "
             "cleaning up a dead file system mount.";
          NSDictionary<NSErrorUserInfoKey, id> *userInfo = @{
            NSLocalizedDescriptionKey: description
          };
          NSError *error = [NSError errorWithDomain:kGMUserFileSystemErrorDomain
                                               code:GMUserFileSystem_ERROR_UNMOUNT_DEADFS_RMDIR
                                           userInfo:userInfo];
          [self postMountError:error];
          [pool release];
          return;
        }
      }
    }
  }

  // Check mount path as necessary.
  struct stat stat_buf;
  memset(&stat_buf, 0, sizeof(stat_buf));
  ret = stat(internal_.mountPath.UTF8String, &stat_buf);
  if ((ret == 0 && !S_ISDIR(stat_buf.st_mode)) ||
      (ret != 0 && errno == ENOTDIR)) {
    [self postMountError:[GMUserFileSystem errorWithCode:ENOTDIR]];
    [pool release];
    return;
  }

  // Trigger initialization of NSFileManager. This is rather lame, but if we
  // don't call directoryContents before we mount our FUSE filesystem and
  // the filesystem uses NSFileManager we may deadlock. It seems that the
  // NSFileManager class will do lazy init and will query all mounted
  // filesystems. This leads to deadlock when we re-enter our mounted FUSE file
  // system. Once initialized it seems to work fine.
  NSFileManager *fileManager = [[NSFileManager alloc] init];
  [fileManager contentsOfDirectoryAtPath:@"/Volumes" error:nil];
  [fileManager release];

  NSMutableArray<NSString *> *arguments =
    [NSMutableArray arrayWithObject:[[NSBundle mainBundle] executablePath]];
  if (!isThreadSafe) {
    [arguments addObject:@"-s"];  // Force single-threaded mode.
  }
  if (shouldForeground) {
    [arguments addObject:@"-f"];  // Forground rather than daemonize.
  }
  for (int i = 0; i < options.count; ++i) {
    NSString *option = options[i];
    if ([option length] > 0) {
      [arguments addObject:[NSString stringWithFormat:@"-o%@", option]];
    }
  }
  [arguments addObject:internal_.mountPath];
  [args release];  // We don't need packaged up args any more.

  // Start fuse_main()
  int argc = (int)arguments.count;
  const char *argv[argc];
  for (int i = 0, count = (int)arguments.count; i < count; i++) {
    NSString *argument = arguments[i];
    argv[i] = strdup(argument.UTF8String);  // We'll just leak this for now.
  }
  if ([internal_.delegate respondsToSelector:@selector(willMount)]) {
    [internal_.delegate willMount];
  }
  [pool release];
  ret = fusefm_main(argc, (char **)argv, &fusefm_oper, self);

  pool = [[NSAutoreleasePool alloc] init];

  if (internal_.status == GMUserFileSystem_MOUNTING) {
    // If we returned from fuse_main while we still think we are
    // mounting then an error must have occurred during mount.
    NSString *description = [NSString stringWithFormat:@
      "Internal FUSE error (rc=%d) while attempting to mount the file system. "
      "For now, the best way to diagnose is to look for error messages using "
      "Console.", ret];
    NSDictionary<NSErrorUserInfoKey, id> *userInfo = @{
      NSLocalizedDescriptionKey: description
    };
    NSError *error = [NSError errorWithDomain:kGMUserFileSystemErrorDomain
                                         code:GMUserFileSystem_ERROR_MOUNT_FUSE_MAIN_INTERNAL
                                     userInfo:userInfo];
    [self postMountError:error];
  } else {
    internal_.status = GMUserFileSystem_NOT_MOUNTED;
  }

  [pool release];
}

@end

NS_ASSUME_NONNULL_END
