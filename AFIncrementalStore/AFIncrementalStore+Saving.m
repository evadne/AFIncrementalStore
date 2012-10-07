//  AFIncrementalStore+Saving.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStore+Saving.h"

@implementation AFIncrementalStore (Saving)

- (id) executePersistentStoreSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	NSArray * (^map)(NSArray *, id(^)(id, NSUInteger)) = ^ (NSArray *array, id(^block)(id, NSUInteger)) {
		
		if (!block || ![array count])
			return array;
		
		NSMutableArray *answer = [NSMutableArray arrayWithCapacity:[array count]];
		[array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			[answer addObject:block(obj, idx)];
		}];
		
		return (NSArray *)answer;
		
	};
	
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
	
	AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	NSURLRequest * (^request)(NSString *, NSManagedObject *, NSManagedObjectContext *) = ^ (NSString *method, NSManagedObject *object, NSManagedObjectContext *context) {
	
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
		
	};
	
	NSMutableArray *requests = [NSMutableArray array];
	
	for (NSManagedObject *insertedObject in [insertedObjects copy])
		[requests addObject:request(@"POST", insertedObject, context)];
	
	for (NSManagedObject *updatedObject in [updatedObjects copy])
		[requests addObject:request(@"POST", updatedObject, context)];
	
	for (NSManagedObject *deletedObject in [deletedObjects copy])
		[requests addObject:request(@"DELETE", deletedObject, context)];

	for (NSManagedObject *lockedObject in [lockedObjects copy])
		[requests addObject:request(@"GET", lockedObject, context)];
	
	NSArray *operations = map(requests, ^ (NSURLRequest *request, NSUInteger index) {
	
		AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
		
			NSLog(@"%@ %s %@ %@", NSStringFromSelector(_cmd), __PRETTY_FUNCTION__, operation, responseObject);
			
		} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
			
			NSLog(@"%@ %s %@ %@", NSStringFromSelector(_cmd), __PRETTY_FUNCTION__, operation, error);
			
		}];
		
		return operation;

	});
	
	[httpClient.operationQueue addOperations:operations waitUntilFinished:YES];
	
	for (AFHTTPRequestOperation *operation in operations) {
		NSCParameterAssert([operation isFinished]);
		if (![operation hasAcceptableStatusCode]) {
			if (error) {
				*error = AFIncrementalStoreError(operation.response.statusCode, [NSString stringWithFormat:@"Operation %@ failed with error.", operation]);
			}
			return nil;
		}
	}
	
	return @[];

}

@end
