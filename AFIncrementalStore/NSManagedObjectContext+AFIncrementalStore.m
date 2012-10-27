#import "NSManagedObject+AFIncrementalStore.h"
#import "NSManagedObjectContext+AFIncrementalStore.h"
#import "RASchedulingKit.h"

const void * kDispatchQueue = &kDispatchQueue;
const void * kIgnoringCount = &kIgnoringCount;

@implementation NSManagedObjectContext (AFIncrementalStore)

- (dispatch_queue_t) af_dispatchQueue {

	dispatch_queue_t queue = objc_getAssociatedObject(self, &kDispatchQueue);
	if (!queue) {
		queue = dispatch_queue_create([NSStringFromClass([self class]) UTF8String], DISPATCH_QUEUE_SERIAL);
		objc_setAssociatedObject(self, &kDispatchQueue, queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	
	return queue;

}

- (BOOL) af_isDescendantOfContext:(NSManagedObjectContext *)context {

	if (self == context)
		return YES;
	
	if (!self.parentContext)
		return NO;
	
	return [self.parentContext af_isDescendantOfContext:context];

}

- (void) af_executeFetchRequest:(NSFetchRequest *)fetchRequest usingBlock:(void(^)(id results, NSError *error))block {

	NSCParameterAssert(fetchRequest);
	NSCParameterAssert(block);
	
	[self performBlock:^{
	
		NSError *error = nil;
		id results = [self executeFetchRequest:fetchRequest error:&error];
		
		if (block)
			block(results, error);
		
	}];

}

- (void) af_performBlock:(void(^)())block {

	switch (self.concurrencyType) {
	
		case NSMainQueueConcurrencyType:
		case NSPrivateQueueConcurrencyType: {
			[self performBlock:block];
			break;
		}
		
		case NSConfinementConcurrencyType: {
			block();
			break;
		}
	
	}
	
}

- (void) af_performBlockAndWait:(void(^)())block {

	switch (self.concurrencyType) {
	
		case NSMainQueueConcurrencyType: {
			
			[self performBlockAndWait:block];
			
			break;
			
		}
		
		case NSPrivateQueueConcurrencyType:
		case NSConfinementConcurrencyType: {
			
			if (self.parentContext) {
				
				[self.parentContext af_performBlockAndWait:block];
				
			} else {

				dispatch_sync([self af_dispatchQueue], ^{
					
					[self performBlockAndWait:block];
					
				});
			
			}
			
			break;
			
		}
	
	}
	
}

- (NSUInteger) af_ignoringCount {

	return [objc_getAssociatedObject(self, &kIgnoringCount) unsignedIntegerValue];

}

- (void) af_setIgnoringCount:(NSUInteger)count {

	objc_setAssociatedObject(self, &kIgnoringCount, [NSNumber numberWithUnsignedInteger:count], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	
}

- (void) af_incrementIgnoringCount {

	NSUInteger count = [self af_ignoringCount];
	
	[self af_setIgnoringCount:(count + 1)];

}

- (void) af_decrementIgnoringCount {

	NSUInteger count = [self af_ignoringCount];
	NSCParameterAssert(count);
	
	[self af_setIgnoringCount:(count - 1)];

}

- (void) af_saveObjects:(NSArray *)objects {
	
	for (NSManagedObject *object in objects) {
		NSCParameterAssert(object.managedObjectContext == self);
		NSCParameterAssert([object af_isPermanent]);
	}
	
	[self af_performBlockAndWait:^{
		NSError *backingContextSavingError;
		if (![self save:&backingContextSavingError]) {
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Saving failed." userInfo:@{
			 NSUnderlyingErrorKey: backingContextSavingError
			}];
		}
	}];
	
	for (NSManagedObject *object in objects)
		NSCParameterAssert(![[object changedValues] count]);
	
}

- (void) af_refreshObjects:(NSArray *)objects {
	
	for (NSManagedObject *object in objects)
		NSCParameterAssert([object af_isPermanent]);
	
	NSSet *refreshedObjects = [NSSet setWithArray:objects];
	NSManagedObjectContext *parentContext = self.parentContext;
	
	[parentContext af_performBlock:^{
		
		[parentContext af_incrementIgnoringCount];
		
		for (NSManagedObject *registeredObject in refreshedObjects) {
			
			NSManagedObject *rootObject = [parentContext objectWithID:registeredObject.objectID];
			
			[rootObject willChangeValueForKey:@"self"];
			[parentContext refreshObject:rootObject mergeChanges:NO];
			[rootObject didChangeValueForKey:@"self"];
			
			NSCParameterAssert(![[rootObject changedValues] count]);
			
		}
		
		[parentContext processPendingChanges];
		[parentContext af_decrementIgnoringCount];
		
		[self af_performBlock:^{
			
			[self af_incrementIgnoringCount];
			
			for (NSManagedObject *registeredObject in refreshedObjects) {
				
				[registeredObject willChangeValueForKey:@"self"];
				[self refreshObject:registeredObject mergeChanges:NO];
				[registeredObject didChangeValueForKey:@"self"];
				
				NSCParameterAssert(![[registeredObject changedValues] count]);
				
			}
			
			[self processPendingChanges];
			[self af_decrementIgnoringCount];
			
			for (NSManagedObject *object in objects)
				NSCParameterAssert(![[object changedValues] count]);
			
		}];
		
	}];
	
}

@end
