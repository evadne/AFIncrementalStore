//  AFIncrementalStore+Relationships.m

#import "AFIncrementalStoreReferenceObject.h"
#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Concurrency.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStore+Notifications.h"
#import "AFIncrementalStore+Relationships.h"

@implementation AFIncrementalStore (Relationships)

- (id) newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    if ([self shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context]) {
      
				NSURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForRelationship:relationship forObjectWithID:objectID withContext:context];
        
        if ([request URL] && ![[context existingObjectWithID:objectID error:nil] hasChanges]) {
						
            NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
            
            AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
                id representationOrArrayOfRepresentations = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:responseObject];
                
                NSArray *representations = nil;
                if ([representationOrArrayOfRepresentations isKindOfClass:[NSArray class]]) {
                    representations = representationOrArrayOfRepresentations;
                } else {
                    representations = [NSArray arrayWithObject:representationOrArrayOfRepresentations];
                }
              
								NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
								childContext.parentContext = context;
								childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
								
                [self performBlock:^{
								
                    NSManagedObject *managedObject = [childContext existingObjectWithID:[self objectIDForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID].resourceIdentifier] error:nil];
                    NSManagedObject *backingObject = [backingContext existingObjectWithID:[self objectIDForBackingObjectForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID].resourceIdentifier] error:nil];

                    id mutableBackingRelationshipObjects = [relationship isOrdered] ? [NSMutableOrderedSet orderedSetWithCapacity:[representations count]] : [NSMutableSet setWithCapacity:[representations count]];
                    id mutableManagedRelationshipObjects = [relationship isOrdered] ? [NSMutableOrderedSet orderedSetWithCapacity:[representations count]] : [NSMutableSet setWithCapacity:[representations count]];

                    NSEntityDescription *entity = relationship.destinationEntity;
                    
                    for (NSDictionary *representation in representations) {
                        NSString *relationshipResourceIdentifier = [self.HTTPClient resourceIdentifierForRepresentation:representation ofEntity:entity fromResponse:operation.response];

                        NSManagedObjectID *relationshipObjectID = [self objectIDForBackingObjectForEntity:relationship.destinationEntity withResourceIdentifier:relationshipResourceIdentifier];
                        NSDictionary *relationshipAttributes = [self.HTTPClient attributesForRepresentation:representation ofEntity:entity fromResponse:operation.response];
                        
                        NSManagedObject *backingRelationshipObject = (relationshipObjectID != nil) ? [backingContext existingObjectWithID:relationshipObjectID error:nil] : [NSEntityDescription insertNewObjectForEntityForName:[relationship.destinationEntity name] inManagedObjectContext:backingContext];
                        [backingRelationshipObject setValuesForKeysWithDictionary:relationshipAttributes];
                        [mutableBackingRelationshipObjects addObject:backingRelationshipObject];

                        NSManagedObject *managedRelationshipObject = [childContext existingObjectWithID:[self objectIDForEntity:relationship.destinationEntity withResourceIdentifier:relationshipResourceIdentifier] error:nil];
                        [managedRelationshipObject setValuesForKeysWithDictionary:relationshipAttributes];
                        [mutableManagedRelationshipObjects addObject:managedRelationshipObject];
                        if (relationshipObjectID == nil) {
                            [childContext insertObject:managedRelationshipObject];
                        }
                    }
                    
                    if ([relationship isToMany]) {
                        [managedObject setValue:mutableManagedRelationshipObjects forKey:relationship.name];
                        [backingObject setValue:mutableBackingRelationshipObjects forKey:relationship.name];
                    } else {
                        [managedObject setValue:[mutableManagedRelationshipObjects anyObject] forKey:relationship.name];
                        [backingObject setValue:[mutableBackingRelationshipObjects anyObject] forKey:relationship.name];
                    }
										
										//	Forcibly merge the changes from saving the child context
										//	so the changes are propagated correctly
										
										NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
										NSOperationQueue *queue = [NSOperationQueue mainQueue];
										__block BOOL savedFromNotification = NO;
										
										id observer = [nc addObserverForName:NSManagedObjectContextDidSaveNotification object:childContext queue:queue usingBlock:^(NSNotification *note) {
										
											[context mergeChangesFromContextDidSaveNotification:note];
											
											savedFromNotification = YES;
											
										}];
										
										__block NSError *backingContextSavingError = nil;
										__block BOOL backingContextDidSave = NO;
										[backingContext performBlockAndWait:^{
											backingContextDidSave = [backingContext save:&backingContextSavingError];
										}];
										
										__block NSError *childContextSavingError = nil;
										__block BOOL childContextDidSave = NO;
//										[childContext performBlockAndWait:^{
											childContextDidSave = [childContext save:&childContextSavingError];
//										}];
										        
                    if (!backingContextDidSave || !childContextDidSave) {
											if (error) {
                        NSLog(@"Error Saving: %@; %@", backingContextSavingError, childContextSavingError);
											} else {
												NSCParameterAssert(savedFromNotification);
											}
                    }
										
										[nc removeObserver:observer];
                    
                    [self notifyManagedObjectContext:context aboutRequestOperation:operation];
                }];
            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                NSLog(@"Error: %@, %@", operation, error);
                [self notifyManagedObjectContext:context aboutRequestOperation:operation];
            }];
            
            operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
            
            [self notifyManagedObjectContext:context aboutRequestOperation:operation];
            [self.HTTPClient enqueueHTTPRequestOperation:operation];
        }
    }
    
    NSManagedObjectID *backingObjectID = [self objectIDForBackingObjectForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID].resourceIdentifier];
    NSManagedObject *backingObject = (backingObjectID == nil) ? nil : [[self backingManagedObjectContext] existingObjectWithID:backingObjectID error:nil];
    
    if (backingObject && ![backingObject hasChanges]) {
        id backingRelationshipObject = [backingObject valueForKeyPath:relationship.name];
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

- (BOOL) shouldFetchRemoteValuesForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID inManagedObjectContext:(NSManagedObjectContext *)context {

	AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	if ([httpClient respondsToSelector:@selector(shouldFetchRemoteValuesForRelationship:forObjectWithID:inManagedObjectContext:)]) {
	
		return [httpClient shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context];
	
	}
	
	return NO;
	
}

- (void) fetchRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context completion:(void(^)(void))block {

	//	Fire remote call

}

- (void) handleRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID finishedLoadingWithResponse:(NSHTTPURLResponse *)response savingIntoContext:(NSManagedObjectContext *)context completion:(void(^)(void))block {

}

- (id) fetchLocalValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error {

	return nil;

}

@end
