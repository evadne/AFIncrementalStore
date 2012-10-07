//  AFIncrementalStore+Relationships.m

#import "AFIncrementalStoreReferenceObject.h"
#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStore+Notifications.h"
#import "AFIncrementalStore+Relationships.h"

@implementation AFIncrementalStore (Relationships)

- (id) newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    if ([self.HTTPClient respondsToSelector:@selector(shouldFetchRemoteValuesForRelationship:forObjectWithID:inManagedObjectContext:)] && [self.HTTPClient shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context]) {
        NSURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForRelationship:relationship forObjectWithID:objectID withContext:context];
        
        if ([request URL] && ![[context existingObjectWithID:objectID error:nil] hasChanges]) {
            NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
            childContext.parentContext = context;
            childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
						
            NSManagedObjectContext *backingContext = [self backingManagedObjectContext];
            
            [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:childContext queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                [context mergeChangesFromContextDidSaveNotification:note];
            }];
            
            AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
                id representationOrArrayOfRepresentations = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:responseObject];
                
                NSArray *representations = nil;
                if ([representationOrArrayOfRepresentations isKindOfClass:[NSArray class]]) {
                    representations = representationOrArrayOfRepresentations;
                } else {
                    representations = [NSArray arrayWithObject:representationOrArrayOfRepresentations];
                }
                
                [childContext performBlock:^{
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
										                
                    if (![backingContext save:error] || ![childContext save:error]) {
											if (error) {
                        NSLog(@"Error: %@", *error);
											}
                    }
                    
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

@end
