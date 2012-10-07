//  AFIncrementalStore+Fetching.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Fetching.h"
#import "AFIncrementalStore+Importing.h"
#import "AFIncrementalStore+Notifications.h"
#import "AFIncrementalStore+ObjectIDs.h"

@implementation AFIncrementalStore (Fetching)

- (id) executePersistentStoreFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	[self executeRemoteFetchRequest:fetchRequest withContext:context completion:^(BOOL didFinish) {
		
		//	?
		
	}];
	
	return [self executeLocalFetchRequest:fetchRequest withContext:context error:error];

}

- (void) executeRemoteFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context completion:(void(^)(BOOL didFinish))block {

	AFHTTPClient<AFIncrementalStoreHTTPClient> const *httpClient = self.HTTPClient;
	NSURLRequest *request = [httpClient requestForFetchRequest:fetchRequest withContext:context];
	
	if (!request.URL)
		return;
	
	AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, NSHTTPURLResponse *response) {
	
		[self handleRemoteFetchRequest:fetchRequest finishedWithResponse:response savingIntoContext:context completion:^{
		
			[self notifyManagedObjectContext:context aboutRequestOperation:operation forPersistentStoreRequest:fetchRequest];
			
			if (block)
				block(YES);
			
		}];
	
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		
		[self notifyManagedObjectContext:context aboutRequestOperation:operation forPersistentStoreRequest:fetchRequest];
	
		if (block)
			block(NO);
		
	}];
	
	operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
	
	[self notifyManagedObjectContext:context aboutRequestOperation:operation forPersistentStoreRequest:fetchRequest];
	
	[httpClient enqueueHTTPRequestOperation:operation];
	
}

- (void) handleRemoteFetchRequest:(NSFetchRequest *)fetchRequest finishedWithResponse:(NSHTTPURLResponse *)response savingIntoContext:(NSManagedObjectContext *)context completion:(void(^)(void))block {

	NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	childContext.parentContext = context;
	childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
	[childContext performBlock:^{
		
		NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
		NSEntityDescription *entity = fetchRequest.entity;
		NSArray *representations = [self representationsFromResponse:response];
		for (NSDictionary *representation in representations) {
			[self importRepresentation:representation ofEntity:entity withResponse:response context:childContext asManagedObject:nil backingObject:nil];				
		}
		
		NSError *error = nil;
		if (![backingContext save:&error] || ![childContext save:&error]) {
			NSLog(@"Error: %@", error);
		}
		
		if (block)
			block();
		
	}];

}

- (id) executeLocalFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error {

	NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
	
	switch (fetchRequest.resultType) {
		
		case NSManagedObjectResultType: {
			
			fetchRequest = [fetchRequest copy];
			fetchRequest.entity = [NSEntityDescription entityForName:fetchRequest.entityName inManagedObjectContext:backingContext];
			fetchRequest.resultType = NSDictionaryResultType;
			fetchRequest.propertiesToFetch = @[ AFIncrementalStoreResourceIdentifierAttributeName ];
			
			NSArray *results = [backingContext executeFetchRequest:fetchRequest error:error];
			
			NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[results count]];
			for (NSString *resourceIdentifier in [results valueForKeyPath:AFIncrementalStoreResourceIdentifierAttributeName]) {
				
				NSManagedObjectID *objectID = [self objectIDForEntity:fetchRequest.entity withResourceIdentifier:resourceIdentifier];
				NSManagedObject *object = [context objectWithID:objectID];
				[mutableObjects addObject:object];
				
			}
							
			return mutableObjects;
			
		}
		
		case NSManagedObjectIDResultType: {
		
			NSArray *backingObjectIDs = [backingContext executeFetchRequest:fetchRequest error:error];
			NSMutableArray *managedObjectIDs = [NSMutableArray arrayWithCapacity:[backingObjectIDs count]];
			
			for (NSManagedObjectID *backingObjectID in backingObjectIDs) {
				 NSManagedObject *backingObject = [backingContext objectWithID:backingObjectID];
				 NSString *resourceID = [backingObject valueForKey:AFIncrementalStoreResourceIdentifierAttributeName];
				 NSManagedObjectID *objectID = [self objectIDForEntity:fetchRequest.entity withResourceIdentifier:resourceID];
				 NSCParameterAssert([objectID.entity isEqual:fetchRequest.entity]);
				 [managedObjectIDs addObject:objectID];
			}
			
			return managedObjectIDs;
		
		}
		
		case NSDictionaryResultType:
		case NSCountResultType: {
			
			return [backingContext executeFetchRequest:fetchRequest error:error];
			
		}
		
		default: {
			
			return nil;
			
		}
		
	}

}

@end
