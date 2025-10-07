//
//  GMDataBackedFileDelegate.h
//  macFUSE
//

//  Copyright (c) 2024-2025 Benjamin Fleischer.
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

@import Foundation;

#import <macFUSE/GMAvailability.h>

NS_ASSUME_NONNULL_BEGIN

#define GM_EXPORT __attribute__((visibility("default")))

GM_AVAILABLE(2_0)
NS_SWIFT_NAME(DataBackedFileDelegate)
GM_EXPORT
@interface GMDataBackedFileDelegate : NSObject {
 @private
  NSData *data_;
}

+ (instancetype)fileDelegateWithData:(NSData *)data GM_AVAILABLE(2_0);

- (instancetype)initWithData:(NSData *)data GM_AVAILABLE(2_0);

@property (nonatomic, readonly, retain) NSData *data GM_AVAILABLE(2_0);

- (int)readToBuffer:(char *)buffer
               size:(size_t)size
             offset:(off_t)offset
              error:(NSError * _Nullable * _Nonnull)error GM_AVAILABLE(2_0);
@end

GM_AVAILABLE(2_0)
NS_SWIFT_NAME(MutableDataBackedFileDelegate)
GM_EXPORT
@interface GMMutableDataBackedFileDelegate : GMDataBackedFileDelegate

- (instancetype)initWithMutableData:(NSMutableData *)data GM_AVAILABLE(2_0);

- (int)writeFromBuffer:(const char *)buffer
                  size:(size_t)size
                offset:(off_t)offset
                 error:(NSError * _Nullable * _Nonnull)error GM_AVAILABLE(2_0);

- (BOOL)truncateToOffset:(off_t)offset
                   error:(NSError * _Nullable * _Nonnull)error GM_AVAILABLE(2_0);

@end

#undef GM_EXPORT

NS_ASSUME_NONNULL_END
