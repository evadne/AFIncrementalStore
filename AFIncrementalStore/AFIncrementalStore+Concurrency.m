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

@end
