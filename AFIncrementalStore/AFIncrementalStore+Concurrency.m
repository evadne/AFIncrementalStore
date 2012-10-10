//  AFIncrementalStore+Concurrency.m

#import "AFIncrementalStore+Concurrency.h"

@implementation AFIncrementalStore (Concurrency)

- (NSOperationQueue *) operationQueue {
	
	if (!_operationQueue) {
	
		_operationQueue = [[NSOperationQueue alloc] init];
		_operationQueue.maxConcurrentOperationCount = 1;
	
	}
	
	return _operationQueue;

}

- (void) performBlock:(void(^)(void))block {

	[self.operationQueue addOperationWithBlock:block];

}

- (void) performBlockAndWait:(void(^)(void))block {

	NSOperation *op = [NSBlockOperation blockOperationWithBlock:block];
	[self.operationQueue addOperations:@[ op ] waitUntilFinished:YES];
	
}

- (BOOL) isPostponingOperations {
	
	return !!_operationPostponementCascadeCount;

}

- (void) beginPostponingOperations {

	NSCParameterAssert([NSThread isMainThread]);
	
	_operationPostponementCascadeCount++;
	
	if (_operationPostponementCascadeCount == 1)
		[self.operationQueue setSuspended:YES];

}

- (void) endPostponingOperations {

	NSCParameterAssert([NSThread isMainThread]);
	NSCParameterAssert(_operationPostponementCascadeCount);
	
	_operationPostponementCascadeCount--;
	
	if (_operationPostponementCascadeCount == 0)
		[self.operationQueue setSuspended:NO];

}

@end
