//  AFIncrementalStore+Relationships.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Concurrency.h"
#import "AFIncrementalStore+Importing.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStore+Notifications.h"
#import "AFIncrementalStore+Relationships.h"

@implementation AFIncrementalStore (Relationships)

- (id) newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

	NSCParameterAssert(![objectID isTemporaryID]);
	NSCParameterAssert(objectID.entity);
	
	[self fetchRemoteValueForRelationship:relationship forObjectWithID:objectID withContext:context completion:^{
	
		//	?
		
	}];
	
	id localAnswer = [self fetchLocalValueForRelationship:relationship forObjectWithID:objectID withContext:context error:error];
	
	return localAnswer;

}

- (BOOL) shouldFetchRemoteValuesForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID inManagedObjectContext:(NSManagedObjectContext *)context {

	AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	if (![self resourceIdentifierForObjectID:objectID])
		return NO;
	
	if ([httpClient respondsToSelector:@selector(shouldFetchRemoteValuesForRelationship:forObjectWithID:inManagedObjectContext:)]) {
	
		return [httpClient shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context];
	
	}
	
	return NO;
	
}

- (void) fetchRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context completion:(void(^)(void))block {

	if (![self shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context])
		return;

	NSURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForRelationship:relationship forObjectWithID:objectID withContext:context];
	
	if (![request URL])
		return;
	
	if ([[context existingObjectWithID:objectID error:nil] hasChanges])
		return;

	AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {

		[self handleRemoteValueForRelationship:relationship forObjectWithID:objectID finishedLoadingWithResponse:responseObject savingIntoContext:context completion:^{
			
			[self notifyManagedObjectContext:context aboutRequestOperation:operation];
			
		}];
				
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		
		[self notifyManagedObjectContext:context aboutRequestOperation:operation];
		
		if (block)
			block();
		
	}];

	operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);

	[self notifyManagedObjectContext:context aboutRequestOperation:operation];
	[self.HTTPClient enqueueHTTPRequestOperation:operation];
  
}

- (void) handleRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID finishedLoadingWithResponse:(NSHTTPURLResponse *)response savingIntoContext:(NSManagedObjectContext *)context completion:(void(^)(void))block {

	NSEntityDescription *entity = [objectID entity];
	NSCParameterAssert(entity);
	
	NSString *resourceIdentifier = [self resourceIdentifierForObjectID:objectID];
	NSCParameterAssert(resourceIdentifier);
	
	NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	childContext.parentContext = context;
	childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;

	[self performBlock:^{
		
		NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
		
		NSManagedObject *managedObject = [childContext existingObjectWithID:[self objectIDForEntity:entity withResourceIdentifier:resourceIdentifier] error:nil];
		NSManagedObject *backingObject = [backingContext existingObjectWithID:[self objectIDForBackingObjectForEntity:entity withResourceIdentifier:resourceIdentifier] error:nil];

		id representations = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:response];
		
		[self importRepresentation:representations fromResponse:response context:childContext forRelationship:relationship usingManagedObject:managedObject backingObject:backingObject];
		
		__block NSError *backingContextSavingError = nil;
		__block BOOL backingContextDidSave = NO;
		[backingContext performBlockAndWait:^{
			backingContextDidSave = [backingContext save:&backingContextSavingError];
		}];
		
		__block NSError *childContextSavingError = nil;
		__block BOOL childContextDidSave = NO;
		[childContext performBlockAndWait:^{
			childContextDidSave = [childContext save:&childContextSavingError];
		}];
				
		if (!backingContextDidSave || !childContextDidSave)
			NSLog(@"Error Saving: %@; %@", backingContextSavingError, childContextSavingError);
		
		if (block)
			block();
				
	}];

}

- (id) fetchLocalValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error {

	NSManagedObjectID *backingObjectID = [self objectIDForBackingObjectForEntity:[objectID entity] withResourceIdentifier:[self resourceIdentifierForObjectID:objectID]];
	NSManagedObject *backingObject = (backingObjectID == nil) ? nil : [[self backingManagedObjectContext] existingObjectWithID:backingObjectID error:nil];
	
	id backingRelationshipObject = [backingObject valueForKeyPath:relationship.name];
	if (backingObject && ![backingObject hasChanges] && backingRelationshipObject) {
			if ([relationship isToMany]) {
					NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[backingRelationshipObject count]];
					for (NSString *resourceIdentifier in [backingRelationshipObject valueForKeyPath:AFIncrementalStoreResourceIdentifierAttributeName]) {
							NSManagedObjectID *objectID = [self objectIDForEntity:relationship.destinationEntity withResourceIdentifier:resourceIdentifier];
							[mutableObjects addObject:objectID];
					}
											
					return mutableObjects;            
			} else {
					NSString *resourceIdentifier = [backingRelationshipObject valueForKeyPath:AFIncrementalStoreResourceIdentifierAttributeName];
					NSManagedObjectID *objectID = [self objectIDForEntity:relationship.destinationEntity withResourceIdentifier:resourceIdentifier];
					
					return objectID ?: [NSNull null];
			}
	} else {
			if ([relationship isToMany]) {
					return [NSArray array];
			} else {
					return [NSNull null];
			}
	}

}

@end
