//  AFIncrementalStore+Saving.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Concurrency.h"
#import "AFIncrementalStore+Importing.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStore+Saving.h"

@implementation AFIncrementalStore (Saving)

- (id) executePersistentStoreSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	
	/*
	
		The idea for change request fulfillement has several assumptions:
		
		a) Objects can either be inserted, updated, deleted or locked.
		b) Locked objects are refreshed with remote state, their original state disposed.
		c) GET requests will be fired for inserted objects
		d) POST requests will be fied for updated objects
		e) DELETE requests will be fired for deleted objects
		f) GET requests will be fired for locked objects
		
		Whenever the remote response returns an acceptible state,
		the representation is used to refresh the backing store.
		
		A previous fundamental assumption of the framework is that **each** entity specified in the model would have its corresponding root-level namespace, for example an Entry would have /entry, and so on.  This will not hold true for hierarchical relationships, but fortunately can be worked around on the HTTP client layer.  However it falls apart when some entities are auxiliary and do not have their remote root-level namespaces.
		
		The solution addressing that problem are related to how objects are serialized.
		
			- requestWithMethod:pathForObjectWithID:withContext:
		
		…might, in some cases, emit a POST call for something else, a DELETE call for something else, or even return nil: no call at all, for auxiliary objects.
	
	*/
	
	//	Go through the entire object graph
	//	Sort the objects
	//	then find eligible entry points
	//	For every single object
	
	AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	childContext.parentContext = context;
	childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
	
	NSArray *entityOperations = [self operationsForSaveChangesRequest:saveChangesRequest savingIntoManagedObjectContext:childContext];
	NSMutableArray *operations = [entityOperations mutableCopy];
	
	NSOperation *tailOperation = [NSBlockOperation blockOperationWithBlock:^{
			
		for (AFHTTPRequestOperation *operation in entityOperations) {
			NSCParameterAssert([operation isFinished]);
			if (![operation hasAcceptableStatusCode]) {
				NSLog(@"Operation %@ failed with error, not saving.", operation);
				return;
			}
		}

		[self performBlock:^{
		
			NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
			
			__block BOOL backingContextDidSave = NO;
			__block NSError *backingContextSavingError = nil;
			[backingContext performBlockAndWait:^{
				backingContextDidSave = [backingContext save:&backingContextSavingError];
			}];
			if (!backingContextDidSave) {
				NSLog(@"Backing context saving error: %@", backingContextSavingError);
				return;
			}
			
			__block BOOL childContextDidSave = NO;
			__block NSError *childContextSavingError = nil;
			[childContext performBlockAndWait:^{
				childContextDidSave = [childContext save:&childContextSavingError];
			}];
			if (!childContextDidSave) {
				NSLog(@"Child context saving error: %@", childContextSavingError);
			}
			
		}];

	}];
	
	for (NSOperation *op in operations)
		[tailOperation addDependency:op];
	
	[operations addObject:tailOperation];
		
	[httpClient.operationQueue addOperations:operations waitUntilFinished:NO];
	
	return @[];

}

- (NSArray *) operationsForSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest savingIntoManagedObjectContext:(NSManagedObjectContext *)childContext {

	NSSet *insertedObjects = [saveChangesRequest insertedObjects];
	NSSet *updatedObjects = [saveChangesRequest updatedObjects];
	NSSet *deletedObjects = [saveChangesRequest deletedObjects];
	NSSet *lockedObjects = [saveChangesRequest lockedObjects];
	
	NSCParameterAssert(![insertedObjects intersectsSet:updatedObjects]);
	NSCParameterAssert(![insertedObjects intersectsSet:deletedObjects]);
	NSCParameterAssert(![insertedObjects intersectsSet:lockedObjects]);
	NSCParameterAssert(![updatedObjects intersectsSet:deletedObjects]);
	NSCParameterAssert(![updatedObjects intersectsSet:lockedObjects]);
	NSCParameterAssert(![deletedObjects intersectsSet:lockedObjects]);
	
	NSMutableArray *operations = [NSMutableArray array];
	
	NSArray * (^map)(NSArray *, id(^)(id, NSUInteger)) = ^ (NSArray *array, id(^block)(id, NSUInteger)) {
		
		if (!block || ![array count])
			return array;
		
		NSMutableArray *answer = [NSMutableArray arrayWithCapacity:[array count]];
		[array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			[answer addObject:block(obj, idx)];
		}];
		
		return (NSArray *)answer;
		
	};
	
	[operations addObjectsFromArray:map([insertedObjects allObjects], ^ (NSManagedObject *obj, NSUInteger idx) {
		
		return [self importOperationWithRequest:[self requestForInsertedObject:obj context:childContext] resultEntity:obj.entity context:childContext];
		
	})];
	
	return operations;

}

- (AFHTTPRequestOperation *) importOperationWithRequest:(NSURLRequest *)urlRequest resultEntity:(NSEntityDescription *)entity context:(NSManagedObjectContext *)childContext {

	AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:urlRequest success:^(AFHTTPRequestOperation *operation, id responseObject) {
	
		[self performBlock:^{
		
			NSArray *representations = [self representationsFromResponse:responseObject];
			NSCParameterAssert([representations count] == 1);
			NSDictionary *representation = [representations lastObject];
			
			[self importRepresentation:representation ofEntity:entity withResponse:responseObject context:childContext asManagedObject:nil backingObject:nil];
				
		}];
	
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		
		NSLog(@"%@ %s %@ %@", NSStringFromSelector(_cmd), __PRETTY_FUNCTION__, operation, error);
		
	}];
	
	return operation;

}

- (NSURLRequest *) requestForHTTPMethod:(NSString *)method object:(NSManagedObject *)object context:(NSManagedObjectContext *)context {

	AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	NSManagedObjectID *objectID = [object objectID];
	NSEntityDescription *objectEntity = [objectID entity];
	
	NSDictionary *representation = [httpClient representationForObject:object];
	NSString *resourceIdentifier = [httpClient resourceIdentifierForRepresentation:representation ofEntity:objectEntity fromResponse:nil];
	
	NSManagedObjectID *backingObjectID = [self objectIDForBackingObjectForEntity:objectEntity withResourceIdentifier:resourceIdentifier];
	
	if (!backingObjectID && ([method isEqualToString:@"POST"] || [method isEqualToString:@"PUT"])) {
	
		return (NSURLRequest *)[httpClient requestWithMethod:method path:[httpClient pathForEntity:object.entity] parameters:[httpClient representationForObject:object]];
	
	} else {

		return [httpClient requestWithMethod:method pathForObjectWithID:objectID withContext:context];
	
	}

}

- (NSURLRequest *) requestForInsertedObject:(NSManagedObject *)object context:(NSManagedObjectContext *)context {

	return [self requestForHTTPMethod:@"POST" object:object context:context];

}

- (NSURLRequest *) requestForUpdatedObject:(NSManagedObject *)object context:(NSManagedObjectContext *)context {
	
	return [self requestForHTTPMethod:@"POST" object:object context:context];

}

- (NSURLRequest *) requestForDeletedObject:(NSManagedObject *)object context:(NSManagedObjectContext *)context {

	return [self requestForHTTPMethod:@"DELETE" object:object context:context];
	
}

- (NSURLRequest *) requestForLockedObject:(NSManagedObject *)object context:(NSManagedObjectContext *)context {

	return [self requestForHTTPMethod:@"GET" object:object context:context];
	
}

@end
