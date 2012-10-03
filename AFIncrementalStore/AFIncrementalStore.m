// AFIncrementalStore.m
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFIncrementalStore.h"
#import "AFHTTPClient.h"

NSString * const AFIncrementalStoreUnimplementedMethodException = @"com.alamofire.incremental-store.exceptions.unimplemented-method";
NSString * const AFIncrementalStoreRelationshipCardinalityException = @"com.alamofire.incremental-store.exceptions.relationship-cardinality";

NSString * const AFIncrementalStoreContextWillFetchRemoteValues = @"AFIncrementalStoreContextWillFetchRemoteValues";
NSString * const AFIncrementalStoreContextDidFetchRemoteValues = @"AFIncrementalStoreContextDidFetchRemoteValues";
NSString * const AFIncrementalStoreRequestOperationKey = @"AFIncrementalStoreRequestOperation";
NSString * const AFIncrementalStorePersistentStoreRequestKey = @"AFIncrementalStorePersistentStoreRequest";

static NSString * const kAFIncrementalStoreResourceIdentifierAttributeName = @"__af_resourceIdentifier";

extern NSError * AFIncrementalStoreError (NSUInteger code, NSString *localizedDescription);

@interface AFIncrementalStore ()
- (NSManagedObjectContext *)backingManagedObjectContext;
- (NSManagedObjectID *)objectIDForEntity:(NSEntityDescription *)entity
                  withResourceIdentifier:(NSString *)resourceIdentifier;
- (NSManagedObjectID *)objectIDForBackingObjectForEntity:(NSEntityDescription *)entity
                                  withResourceIdentifier:(NSString *)resourceIdentifier;
- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
             aboutRequestOperation:(AFHTTPRequestOperation *)operation;
- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
             aboutRequestOperation:(AFHTTPRequestOperation *)operation
         forPersistentStoreRequest:(NSPersistentStoreRequest *)request;
@end

@implementation AFIncrementalStore {
@private
    NSCache *_propertyValuesCache;
    NSCache *_relationshipsCache;
    NSCache *_backingObjectIDByObjectID;
    NSMutableDictionary *_registeredObjectIDsByResourceIdentifier;
    NSPersistentStoreCoordinator *_backingPersistentStoreCoordinator;
    NSManagedObjectContext *_backingManagedObjectContext;
}
@synthesize HTTPClient = _HTTPClient;
@synthesize backingPersistentStoreCoordinator = _backingPersistentStoreCoordinator;

+ (NSString *)type {
    @throw([NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:NSLocalizedString(@"Unimplemented method: +type. Must be overridden in a subclass", nil) userInfo:nil]);
}

+ (NSManagedObjectModel *)model {
    @throw([NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:NSLocalizedString(@"Unimplemented method: +model. Must be overridden in a subclass", nil) userInfo:nil]);
}

- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
             aboutRequestOperation:(AFHTTPRequestOperation *)operation
{
    [self notifyManagedObjectContext:context aboutRequestOperation:operation forPersistentStoreRequest:nil];
}

- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
             aboutRequestOperation:(AFHTTPRequestOperation *)operation
         forPersistentStoreRequest:(NSPersistentStoreRequest *)request
{
    NSString *notificationName = [operation isFinished] ? AFIncrementalStoreContextDidFetchRemoteValues : AFIncrementalStoreContextWillFetchRemoteValues;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:operation forKey:AFIncrementalStoreRequestOperationKey];
    if (request) {
        [userInfo setObject:request forKey:AFIncrementalStorePersistentStoreRequestKey];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:context userInfo:userInfo];
}

- (BOOL)loadMetadata:(NSError *__autoreleasing *)error {
    if (!_propertyValuesCache) {
        NSMutableDictionary *mutableMetadata = [NSMutableDictionary dictionary];
        [mutableMetadata setValue:[[NSProcessInfo processInfo] globallyUniqueString] forKey:NSStoreUUIDKey];
        [mutableMetadata setValue:NSStringFromClass([self class]) forKey:NSStoreTypeKey];
        [self setMetadata:mutableMetadata];
        
        _propertyValuesCache = [[NSCache alloc] init];
        _relationshipsCache = [[NSCache alloc] init];
        _backingObjectIDByObjectID = [[NSCache alloc] init];
        _registeredObjectIDsByResourceIdentifier = [[NSMutableDictionary alloc] init];
        
        NSManagedObjectModel *model = [self.persistentStoreCoordinator.managedObjectModel copy];
        for (NSEntityDescription *entity in model.entities) {
            // Don't add resource identifier property for sub-entities, as they already exist in the super-entity 
            if ([entity superentity]) {
                continue;
            }
            
            NSAttributeDescription *resourceIdentifierProperty = [[NSAttributeDescription alloc] init];
            [resourceIdentifierProperty setName:kAFIncrementalStoreResourceIdentifierAttributeName];
            [resourceIdentifierProperty setAttributeType:NSStringAttributeType];
            [resourceIdentifierProperty setIndexed:YES];
            [entity setProperties:[entity.properties arrayByAddingObject:resourceIdentifierProperty]];
        }
        
        _backingPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        
        return YES;
    } else {
        return NO;
    }
}

- (NSManagedObjectContext *)backingManagedObjectContext {
    if (!_backingManagedObjectContext) {
        _backingManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        _backingManagedObjectContext.persistentStoreCoordinator = _backingPersistentStoreCoordinator;
        _backingManagedObjectContext.retainsRegisteredObjects = YES;
    }
    
    return _backingManagedObjectContext;
}

- (NSManagedObjectID *)objectIDForEntity:(NSEntityDescription *)entity
                  withResourceIdentifier:(NSString *)resourceIdentifier {
    NSManagedObjectID *objectID = [_registeredObjectIDsByResourceIdentifier objectForKey:resourceIdentifier];
    if (objectID == nil) {
        objectID = [self newObjectIDForEntity:entity referenceObject:resourceIdentifier];
    }
    
    return objectID;
}

- (NSManagedObjectID *)objectIDForBackingObjectForEntity:(NSEntityDescription *)entity
                                  withResourceIdentifier:(NSString *)resourceIdentifier
{
    if (!resourceIdentifier) {
        return nil;
    }
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:[entity name]];
    fetchRequest.resultType = NSManagedObjectIDResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", kAFIncrementalStoreResourceIdentifierAttributeName, resourceIdentifier];
    
    NSError *error = nil;
    NSArray *results = [[self backingManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
    if (error) {
        NSLog(@"Error: %@", error);
        return nil;
    }
    
    return [results lastObject];
}

# pragma mark - Request Dispatch

- (id) executeRequest:(NSPersistentStoreRequest *)persistentStoreRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	NSPersistentStoreRequestType const requestType = [persistentStoreRequest requestType];
	
	if (requestType == NSFetchRequestType)
	if ([persistentStoreRequest isKindOfClass:[NSFetchRequest class]]) {
		return [self executePersistentStoreFetchRequest:(NSFetchRequest *)persistentStoreRequest withContext:context error:error];
	}
	
	if (requestType == NSSaveRequestType)
	if ([persistentStoreRequest isKindOfClass:[NSSaveChangesRequest class]]) {
		return [self executePersistentStoreSaveChangesRequest:(NSSaveChangesRequest *)persistentStoreRequest withContext:context error:error];
	}
	
	if (error) {
		*error = AFIncrementalStoreError(0, [NSString stringWithFormat:NSLocalizedString(@"Unsupported NSFetchRequestResultType, %d", nil), persistentStoreRequest.requestType]);
	}
	
	return nil;
	
}

# pragma mark - Handling Fetch

- (id) executePersistentStoreFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	[self executeRemoteFetchRequest:fetchRequest withContext:context completion:^(BOOL didFinish) {
		
		//	?
		
		NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
		context.persistentStoreCoordinator = self.persistentStoreCoordinator;
		[context save:nil];
		
	}];
	
	return [self executeLocalFetchRequest:fetchRequest withContext:context error:error];

}

- (void) importRepresentation:(NSDictionary *)representation ofEntity:(NSEntityDescription *)entity withResponse:(NSHTTPURLResponse *)response context:(NSManagedObjectContext *)childContext asManagedObject:(NSManagedObject **)outManagedObject backingObject:(NSManagedObject **)outBackingObject {

	__weak AFIncrementalStore *wSelf = self;
	__weak AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	NSManagedObjectContext *backingContext = [self backingManagedObjectContext];

	NSManagedObject * (^insertedObject)(NSManagedObjectContext *, NSEntityDescription *, NSString *, NSDictionary *) = ^ (NSManagedObjectContext *context, NSEntityDescription *entity, NSString *resourceIdentifier, NSDictionary *attributes) {

		NSManagedObjectID *objectID = [wSelf objectIDForBackingObjectForEntity:entity withResourceIdentifier:resourceIdentifier];
		NSManagedObject *object = objectID ?
			[context existingObjectWithID:objectID error:nil] :
			[NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:context];
		
		[object setValuesForKeysWithDictionary:attributes];

		return object;

	};

	NSManagedObject * (^insertedManagedObject)(NSEntityDescription *, NSString *, NSDictionary *) = ^ (NSEntityDescription *entity, NSString *resourceIdentifier, NSDictionary *attributes) {

		NSManagedObject *object = insertedObject(childContext, entity, resourceIdentifier, attributes);
		
		return object;
		
	};

	NSManagedObject * (^insertedBackingObject)(NSEntityDescription *, NSString *, NSDictionary *) = ^ (NSEntityDescription *entity, NSString *resourceIdentifier, NSDictionary *attributes) {

		NSManagedObject *object = insertedObject(backingContext, entity, resourceIdentifier, attributes);
		[object setValue:resourceIdentifier forKey:kAFIncrementalStoreResourceIdentifierAttributeName];
		
		return object;

	};
	
	NSString *resourceIdentifier = [httpClient resourceIdentifierForRepresentation:representation ofEntity:entity fromResponse:response];
	NSDictionary *attributes = [httpClient attributesForRepresentation:representation ofEntity:entity fromResponse:response];
	
	NSManagedObject *managedObject = insertedManagedObject(entity, resourceIdentifier, attributes);
	NSManagedObject *backingObject = insertedBackingObject(entity, resourceIdentifier, attributes);
	
	if (outManagedObject)
		*outManagedObject = managedObject;

	if (outBackingObject)
		*outBackingObject = backingObject;
	
	if (![backingObject objectID] || [[backingObject objectID] isTemporaryID]) {
		[childContext insertObject:managedObject];
	}
	
	NSDictionary *relationshipRepresentations = [httpClient representationsForRelationshipsFromRepresentation:representation ofEntity:entity fromResponse:response];
	
	for (NSString *relationshipName in relationshipRepresentations) {
	
		NSRelationshipDescription *relationship = [[entity relationshipsByName] valueForKey:relationshipName];
		NSCParameterAssert(relationship);
		
		if ([relationship isToMany]) {
		
			NSArray *representations = (NSArray *)[relationshipRepresentations objectForKey:relationship.name];
			if (![representations isKindOfClass:[NSArray class]]) {
				@throw([NSException exceptionWithName:AFIncrementalStoreRelationshipCardinalityException reason:NSLocalizedString(@"Cardinality of provided resource representation conflicts with Core Data model.", nil) userInfo:nil]);
			}
			
			id mutableManagedRelationshipObjects = [relationship isOrdered] ? [NSMutableOrderedSet orderedSet] : [NSMutableSet set];
			id mutableBackingRelationshipObjects = [relationship isOrdered] ? [NSMutableOrderedSet orderedSet] : [NSMutableSet set];
			
			for (NSDictionary *representation in representations) {
			
				NSManagedObject *managedObject = nil;
				NSManagedObject *backingObject = nil;
				
				[self importRepresentation:representation ofEntity:entity withResponse:response context:childContext asManagedObject:&managedObject backingObject:&backingObject];
				
				[mutableManagedRelationshipObjects addObject:managedObject];
				[mutableBackingRelationshipObjects addObject:backingObject];
					
			}

			[managedObject setValue:mutableManagedRelationshipObjects forKey:relationship.name];
			[backingObject setValue:mutableBackingRelationshipObjects forKey:relationship.name];
		
		} else {
		
			NSDictionary *representation = (NSDictionary *)[relationshipRepresentations objectForKey:relationship.name];
			if (![representation isKindOfClass:[NSDictionary class]]) {
				@throw([NSException exceptionWithName:AFIncrementalStoreRelationshipCardinalityException reason:NSLocalizedString(@"Cardinality of provided resource representation conflicts with Core Data model.", nil) userInfo:nil]);
			}
			
			NSManagedObject *managedRelationshipObject = nil;
			NSManagedObject *backingRelationshipObject = nil;
			
			[self importRepresentation:representation ofEntity:entity withResponse:response context:childContext asManagedObject:&managedRelationshipObject backingObject:&backingRelationshipObject];
			
			[backingObject setValue:backingRelationshipObject forKey:relationship.name];
			[managedObject setValue:managedRelationshipObject forKey:relationship.name];
		
		}
	
	}

}

- (NSArray *) representationsFromResponse:(NSHTTPURLResponse *)response {

	id repOrReps = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:response];
	
	if ([repOrReps isKindOfClass:[NSDictionary class]])
		return [NSArray arrayWithObject:repOrReps];
	
	if ([repOrReps isKindOfClass:[NSArray class]])
		return (NSArray *)repOrReps;
	
	return nil;

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
			fetchRequest.propertiesToFetch = @[ kAFIncrementalStoreResourceIdentifierAttributeName ];
			
			NSArray *results = [backingContext executeFetchRequest:fetchRequest error:error];
			
			NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[results count]];
			for (NSString *resourceIdentifier in [results valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName]) {
				
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
				 NSString *resourceID = [backingObject valueForKey:kAFIncrementalStoreResourceIdentifierAttributeName];
				 
				 [managedObjectIDs addObject:[self objectIDForEntity:fetchRequest.entity withResourceIdentifier:resourceID]];
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

# pragma mark - Handling Save

- (id) executePersistentStoreSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	[NSException raise:AFIncrementalStoreUnimplementedMethodException format:@"%s is not implemented.", __PRETTY_FUNCTION__];

	return @[];

}

#pragma mark -

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError *__autoreleasing *)error
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:[[objectID entity] name]];
    fetchRequest.resultType = NSDictionaryResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesSubentities = NO;
    fetchRequest.propertiesToFetch = [[[NSEntityDescription entityForName:fetchRequest.entityName inManagedObjectContext:context] attributesByName] allKeys];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", kAFIncrementalStoreResourceIdentifierAttributeName, [self referenceObjectForObjectID:objectID]];
    
    NSArray *results = [[self backingManagedObjectContext] executeFetchRequest:fetchRequest error:error];
    NSDictionary *attributeValues = [results lastObject] ?: [NSDictionary dictionary];

    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:attributeValues version:1];
    
    if ([self.HTTPClient respondsToSelector:@selector(shouldFetchRemoteAttributeValuesForObjectWithID:inManagedObjectContext:)] && [self.HTTPClient shouldFetchRemoteAttributeValuesForObjectWithID:objectID inManagedObjectContext:context]) {
        if (attributeValues) {
            NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
            childContext.parentContext = context;
            childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
            
            NSURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForObjectWithID:objectID withContext:context];
            
            if ([request URL]) {
                AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, NSDictionary *representation) {
                    NSManagedObject *managedObject = [childContext existingObjectWithID:objectID error:error];
                    
                    NSMutableDictionary *mutablePropertyValues = [attributeValues mutableCopy];
                    [mutablePropertyValues addEntriesFromDictionary:[self.HTTPClient attributesForRepresentation:representation ofEntity:managedObject.entity fromResponse:operation.response]];
                    [managedObject setValuesForKeysWithDictionary:mutablePropertyValues];
                    
                    [childContext performBlock:^{
                        if (![childContext save:error]) {
                            NSLog(@"Error: %@", *error);
                        }
                        
                        [context performBlock:^{
                            if (![context save:error]) {
                                NSLog(@"Error: %@", *error);
                            }
                            
                            [self notifyManagedObjectContext:context aboutRequestOperation:operation];
                        }];
                    }];
                } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                    NSLog(@"Error: %@, %@", operation, error);
                    [self notifyManagedObjectContext:context aboutRequestOperation:operation];
                }];
                
                [self notifyManagedObjectContext:context aboutRequestOperation:operation];
                [self.HTTPClient enqueueHTTPRequestOperation:operation];
            }
        }
    }
    
    return node;
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError *__autoreleasing *)error
{
    if ([self.HTTPClient respondsToSelector:@selector(shouldFetchRemoteValuesForRelationship:forObjectWithID:inManagedObjectContext:)] && [self.HTTPClient shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context]) {
        NSURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForRelationship:relationship forObjectWithID:objectID withContext:context];
        
        if ([request URL] && ![[context existingObjectWithID:objectID error:nil] hasChanges]) {
            NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
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
                    NSManagedObject *managedObject = [childContext existingObjectWithID:[self objectIDForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID]] error:nil];
                    NSManagedObject *backingObject = [backingContext existingObjectWithID:[self objectIDForBackingObjectForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID]] error:nil];

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
                        NSLog(@"Error: %@", *error);
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
    
    NSManagedObjectID *backingObjectID = [self objectIDForBackingObjectForEntity:[objectID entity] withResourceIdentifier:[self referenceObjectForObjectID:objectID]];
    NSManagedObject *backingObject = (backingObjectID == nil) ? nil : [[self backingManagedObjectContext] existingObjectWithID:backingObjectID error:nil];
    
    if (backingObject && ![backingObject hasChanges]) {
        id backingRelationshipObject = [backingObject valueForKeyPath:relationship.name];
        if ([relationship isToMany]) {
            NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[backingRelationshipObject count]];
            for (NSString *resourceIdentifier in [backingRelationshipObject valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName]) {
                NSManagedObjectID *objectID = [self objectIDForEntity:relationship.destinationEntity withResourceIdentifier:resourceIdentifier];
                [mutableObjects addObject:objectID];
            }
                        
            return mutableObjects;            
        } else {
            NSString *resourceIdentifier = [backingRelationshipObject valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName];
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

#pragma mark - NSIncrementalStore

- (void)managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs {
    [super managedObjectContextDidRegisterObjectsWithIDs:objectIDs];
    for (NSManagedObjectID *objectID in objectIDs) {
        [_registeredObjectIDsByResourceIdentifier setObject:objectID forKey:[self referenceObjectForObjectID:objectID]];
    }
}

- (void)managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs {
    [super managedObjectContextDidUnregisterObjectsWithIDs:objectIDs];
    for (NSManagedObjectID *objectID in objectIDs) {
        [_registeredObjectIDsByResourceIdentifier removeObjectForKey:[self referenceObjectForObjectID:objectID]];
    }    
}

@end


NSError * AFIncrementalStoreError (NSUInteger code, NSString *localizedDescription) {

	return [NSError errorWithDomain:AFNetworkingErrorDomain code:code userInfo:@{
		NSLocalizedDescriptionKey: localizedDescription
	}];

};
