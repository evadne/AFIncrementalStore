//  AFIncrementalStore+Concurrency.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (Concurrency)

@property (nonatomic, readonly, strong) NSOperationQueue *operationQueue;

- (void) performBlock:(void(^)(void))block;
- (void) performBlockAndWait:(void(^)(void))block;

@end
