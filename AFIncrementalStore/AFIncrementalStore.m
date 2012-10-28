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

#import <objc/runtime.h>
#import "AFIncrementalStore.h"
#import "AFHTTPClient.h"
#import "ISO8601DateFormatter.h"
#import "NSManagedObject+AFIncrementalStore.h"
#import "NSManagedObjectContext+AFIncrementalStore.h"
#import "RASchedulingKit.h"

NSString * const AFIncrementalStoreUnimplementedMethodException = @"com.alamofire.incremental-store.exceptions.unimplemented-method";
NSString * const AFIncrementalStoreRelationshipCardinalityException = @"com.alamofire.incremental-store.exceptions.relationship-cardinality";

NSString * const AFIncrementalStoreContextWillFetchRemoteValues = @"AFIncrementalStoreContextWillFetchRemoteValues";
NSString * const AFIncrementalStoreContextWillSaveRemoteValues = @"AFIncrementalStoreContextWillSaveRemoteValues";
NSString * const AFIncrementalStoreContextDidFetchRemoteValues = @"AFIncrementalStoreContextDidFetchRemoteValues";
NSString * const AFIncrementalStoreContextDidSaveRemoteValues = @"AFIncrementalStoreContextDidSaveRemoteValues";
NSString * const AFIncrementalStoreRequestOperationKey = @"AFIncrementalStoreRequestOperation";
NSString * const AFIncrementalStorePersistentStoreRequestKey = @"AFIncrementalStorePersistentStoreRequest";

NSString * const kAFIncrementalStoreResourceIdentifierAttributeName = @"__af_resourceIdentifier";
NSString * const kAFIncrementalStoreLastModifiedAttributeName = @"__af_lastModified";

#pragma mark -

@interface AFIncrementalStore ()

@property (nonatomic, readonly, strong) NSManagedObjectModel *backingManagedObjectModel;
@property (nonatomic, readonly, strong) NSManagedObjectContext *backingManagedObjectContext;
@property (nonatomic, readonly, strong) NSOperationQueue *operationQueue;
@property (nonatomic, readonly, strong) dispatch_queue_t dispatchQueue;

@end

@implementation AFIncrementalStore {
@private
    NSCache *_backingObjectIDByObjectID;
    NSMutableDictionary *_registeredObjectIDsByResourceIdentifier;
}
@synthesize HTTPClient = _HTTPClient;
@synthesize backingPersistentStoreCoordinator = _backingPersistentStoreCoordinator;
@synthesize operationQueue = _operationQueue;
@synthesize dispatchQueue = _dispatchQueue;
@synthesize backingManagedObjectModel = _backingManagedObjectModel;
@synthesize backingManagedObjectContext = _backingManagedObjectContext;

# pragma mark - Configuration

+ (NSString *) type {
    
    @throw [NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:@"Must be overridden in a subclass." userInfo:nil];
}

+ (NSManagedObjectModel *) model {
    
    @throw [NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:@"Must be overridden in a subclass." userInfo:nil];
}

- (BOOL) loadMetadata:(NSError *__autoreleasing *)error {
    
    if (!_backingObjectIDByObjectID) {
        
        [self setMetadata:@{
            NSStoreTypeKey: [[self class] type],
            NSStoreUUIDKey: [[NSProcessInfo processInfo] globallyUniqueString]
        }];
        
        _backingObjectIDByObjectID = [[NSCache alloc] init];
        _registeredObjectIDsByResourceIdentifier = [[NSMutableDictionary alloc] init];
        
        return YES;
        
    } else {
        
        return NO;
        
    }
    
}

# pragma mark - Backing Store

- (NSManagedObjectModel *) backingManagedObjectModel {

    if (!_backingManagedObjectModel) {
    
        NSManagedObjectModel *model = [self.persistentStoreCoordinator.managedObjectModel copy];
        
        for (NSEntityDescription *entity in model.entities) {
        
            // Don't add properties for sub-entities, as they already exist in the super-entity 
            if ([entity superentity]) {
                continue;
            }
            
            NSAttributeDescription *resourceIdentifierProperty = [[NSAttributeDescription alloc] init];
            [resourceIdentifierProperty setName:kAFIncrementalStoreResourceIdentifierAttributeName];
            [resourceIdentifierProperty setAttributeType:NSStringAttributeType];
            [resourceIdentifierProperty setIndexed:YES];
            
            NSAttributeDescription *lastModifiedProperty = [[NSAttributeDescription alloc] init];
            [lastModifiedProperty setName:kAFIncrementalStoreLastModifiedAttributeName];
            [lastModifiedProperty setAttributeType:NSDateAttributeType];
            [lastModifiedProperty setIndexed:NO];
            
            [entity setProperties:[entity.properties arrayByAddingObjectsFromArray:[NSArray arrayWithObjects:resourceIdentifierProperty, lastModifiedProperty, nil]]];
            
        }
        
        _backingManagedObjectModel = model;
    
    }
    
    return _backingManagedObjectModel;

}

- (NSPersistentStoreCoordinator *) backingPersistentStoreCoordinator {

    if (!_backingPersistentStoreCoordinator) {
    
        _backingPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.backingManagedObjectModel];
    
    }
    
    return _backingPersistentStoreCoordinator;

}

- (NSManagedObjectContext *) backingManagedObjectContext {
    
    if (!_backingManagedObjectContext) {
        
        _backingManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        _backingManagedObjectContext.persistentStoreCoordinator = self.backingPersistentStoreCoordinator;
        _backingManagedObjectContext.retainsRegisteredObjects = YES;
        
    }
    
    return _backingManagedObjectContext;
    
}

- (NSManagedObject *) backingObjectInContext:(NSManagedObjectContext *)backingContext forManagedObject:(NSManagedObject *)managedObject {

    NSEntityDescription *backingEntity = [NSEntityDescription entityForName:managedObject.entity.name inManagedObjectContext:backingContext];
    NSString *resourceIdentifier = managedObject.af_resourceIdentifier;
    
    if (!backingEntity || !resourceIdentifier)
        return (NSManagedObject *)nil;
    
    NSManagedObjectID *objectID = [self backingObjectIDForEntity:backingEntity resourceIdentifier:resourceIdentifier inContext:backingContext error:nil];
    
    if (!objectID)
        return (NSManagedObject *)nil;
    
    return [backingContext existingObjectWithID:objectID error:nil];;

}

- (NSManagedObjectID *) backingObjectIDForEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)resourceIdentifier inContext:(NSManagedObjectContext *)context error:(NSError **)outError {

    NSCParameterAssert(entity);
    NSCParameterAssert(resourceIdentifier);
    NSCParameterAssert([context af_isDescendantOfContext:self.backingManagedObjectContext]);
    
    NSFetchRequest *fetchRequest = [self fetchRequestForObjectIDWithEntity:entity resourceIdentifier:resourceIdentifier];
    
    __block NSArray *results = nil;
    [context af_performBlockAndWait:^{
       results = [context executeFetchRequest:fetchRequest error:outError];
    }];
    
    return [results lastObject];

}

# pragma mark - Dispatch

- (id) executeRequest:(NSPersistentStoreRequest *)persistentStoreRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {
    
    NSPersistentStoreRequestType type = persistentStoreRequest.requestType;
    
    if (type == NSFetchRequestType) {
        
        NSFetchRequest *fetchRequest = (NSFetchRequest *)persistentStoreRequest;
        NSCParameterAssert([fetchRequest isKindOfClass:[NSFetchRequest class]]);
        
        return [self executeFetchRequest:fetchRequest withContext:context error:error];
        
    } else if (type == NSSaveRequestType) {
        
        NSSaveChangesRequest *saveChangesRequest = (NSSaveChangesRequest *)persistentStoreRequest;
        NSCParameterAssert([saveChangesRequest isKindOfClass:[NSSaveChangesRequest class]]);
        
        return [self executeSaveChangesRequest:saveChangesRequest withContext:context error:error];
        
    } else {
    
        if (error) {
            *error = [NSError errorWithDomain:AFNetworkingErrorDomain code:0 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported NSFetchRequestResultType %d", persistentStoreRequest.requestType]
            }];
        }
        
        return nil;
        
    }
    
}

- (id) executeFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {
    
    NSCParameterAssert(fetchRequest);
    NSCParameterAssert(context);
    
    if ([self shouldExecuteRemoteFetchRequest:fetchRequest withContext:context]) {
    
        [self executeRemoteFetchRequest:fetchRequest withContext:context];
    
    }
    
    return [self executeLocalFetchRequest:fetchRequest withContext:context error:error];

}

- (id) executeSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    
    if ([self shouldExecuteRemoteSaveChangesRequest:saveChangesRequest withContext:context]) {
    
        [self executeRemoteSaveChangesRequest:saveChangesRequest withContext:context];
    
    }
    
    return [self executeLocalSaveChangesRequest:saveChangesRequest withContext:context error:error];
    
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError *__autoreleasing *)error
{
    
    NSIncrementalStoreNode *node = [self retrieveLocalValuesForObjectWithID:objectID context:context error:error];
    
    if ([self shouldRetrieveRemoteValuesForObjectWithID:objectID withContext:context]) {
        
        NSDictionary *properties = objectID.entity.propertiesByName;
        NSPropertyDescription *property = properties[kAFIncrementalStoreLastModifiedAttributeName];
        NSMutableDictionary *options = nil;
        
        NSDate *date = [node valueForPropertyDescription:property];
        if ([date isKindOfClass:[NSDate date]]) {
            options = options ?: [NSMutableDictionary dictionary];
            options[kAFIncrementalStoreLastModifiedAttributeName] = date;
        }
    
        [self retrieveRemoteValueForObjectWithID:objectID context:context options:options];
    
    }
    
    return node;
    
}

- (id) newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    if ([self shouldRetrieveRemoteValueForRelationship:relationship forObjectWithID:objectID withContext:context]) {
    
        [self fetchNewValueForRelationship:relationship forObjectWithID:objectID withContext:context];
        
    }
    
    return [self loadNewValueForRelationship:relationship forObjectWithID:objectID withContext:context error:error];

}

# pragma mark - Fetching

- (BOOL) shouldExecuteRemoteFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context {

    return YES;
    
}

- (void) executeRemoteFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context {

    NSURLRequest *request = [self.HTTPClient requestForFetchRequest:fetchRequest withContext:context];
    if ([request URL]) {
        AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            NSArray *representations = [self representationsFromResponseObject:responseObject];
            
            [self performUpdatesWithManagedContext:context backingContext:self.backingManagedObjectContext usingBlock:^(NSManagedObjectContext *childManagedContext, NSManagedObjectContext *childBackingContext) {
            
                [self importRepresentations:representations ofEntity:fetchRequest.entity fromResponse:operation.response withManagedContext:childManagedContext backingContext:childBackingContext usingBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
                
                    [childBackingContext af_saveObjects:backingObjects];
                    [childBackingContext.parentContext af_performBlockAndWait:^{
                        [childBackingContext.parentContext save:nil];
                    }];
                    [childManagedContext af_refreshObjects:managedObjects];
                
                }];
                
                [self notifyManagedObjectContext:context aboutRequestOperation:operation forFetchRequest:fetchRequest];

            }];
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            [self notifyManagedObjectContext:context aboutRequestOperation:operation forFetchRequest:fetchRequest];
        }];
        
        operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        operation.failureCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        
        [self notifyManagedObjectContext:context aboutRequestOperation:operation forFetchRequest:fetchRequest];
        [self.HTTPClient enqueueHTTPRequestOperation:operation];
    }

}

- (id) executeLocalFetchRequest:(NSFetchRequest *)fetchRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {
    
    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
    __block NSArray *results = nil;
    
    NSFetchRequestResultType resultType = fetchRequest.resultType;
    switch (resultType) {
        case NSManagedObjectResultType: {
            fetchRequest = [fetchRequest copy];
            fetchRequest.entity = [NSEntityDescription entityForName:fetchRequest.entityName inManagedObjectContext:backingContext];
            fetchRequest.resultType = NSDictionaryResultType;
            fetchRequest.propertiesToFetch = @[ kAFIncrementalStoreResourceIdentifierAttributeName ];
            [backingContext af_performBlockAndWait:^{
                results = [backingContext executeFetchRequest:fetchRequest error:error];                
            }];
            
            NSMutableArray *mutableObjects = [NSMutableArray arrayWithCapacity:[results count]];
            for (NSString *resourceIdentifier in [results valueForKeyPath:kAFIncrementalStoreResourceIdentifierAttributeName]) {
                NSManagedObjectID *objectID = [self objectIDForEntity:fetchRequest.entity withResourceIdentifier:resourceIdentifier];
                NSManagedObject *object = [context objectWithID:objectID];
                object.af_resourceIdentifier = resourceIdentifier;
                [mutableObjects addObject:object];
            }
            
            return mutableObjects;
        }
        case NSManagedObjectIDResultType: {
            __block NSArray *backingObjectIDs;
            [backingContext af_performBlockAndWait:^{
                backingObjectIDs = [backingContext executeFetchRequest:fetchRequest error:error];
            }];
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
            [backingContext af_performBlockAndWait:^{
                results = [backingContext executeFetchRequest:fetchRequest error:error];                
            }];
            return results;
        }
        default: {
            return nil;
        }
    }
}

# pragma mark - Values

- (BOOL) shouldRetrieveRemoteValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context {

    if ([context af_ignoringCount])
        return NO;

    NSString *resourceIdentifier = [self referenceObjectForObjectID:objectID];
    if (!resourceIdentifier || (resourceIdentifier && ![resourceIdentifier isKindOfClass:[NSString class]]))
        return NO;
    
    AFHTTPClient<AFIncrementalStoreHTTPClient> *HTTPClient = self.HTTPClient;
    if (!HTTPClient)
        return NO;
    
    if (![HTTPClient respondsToSelector:@selector(shouldFetchRemoteAttributeValuesForObjectWithID:inManagedObjectContext:)])
        return NO;
    
    return [HTTPClient shouldFetchRemoteAttributeValuesForObjectWithID:objectID inManagedObjectContext:context];

}

- (void) retrieveRemoteValueForObjectWithID:(NSManagedObjectID *)objectID context:(NSManagedObjectContext *)context options:(NSDictionary *)options {

    NSDate *lastModified = options[kAFIncrementalStoreLastModifiedAttributeName];
    
    NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    childContext.parentContext = context;
    childContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    
    NSMutableURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForObjectWithID:objectID withContext:context];
    
    if ([request URL]) {
        if (lastModified) {
            [request setValue:[lastModified description] forHTTPHeaderField:@"If-Modified-Since"];
        }
        
        AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, NSDictionary *representation) {
            
            NSManagedObject *managedObject = [childContext existingObjectWithID:objectID error:nil];
            
            NSDictionary *attributeValues = [self.HTTPClient attributesForRepresentation:representation ofEntity:managedObject.entity fromResponse:operation.response];
            
            [managedObject setValuesForKeysWithDictionary:attributeValues];
            
            NSEntityDescription *entity = objectID.entity;
            NSString *resourceID = [self referenceObjectForObjectID:objectID];
            NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
            
            [backingContext performBlock:^{
                
                NSError *backingObjectIDError = nil;
                NSManagedObjectID *backingObjectID = [self backingObjectIDForEntity:entity resourceIdentifier:resourceID inContext:backingContext error:&backingObjectIDError];

                NSManagedObject *backingObject = [backingContext existingObjectWithID:backingObjectID error:nil];
                [backingObject setValuesForKeysWithDictionary:attributeValues];
                
                [backingContext af_saveObjects:@[ backingObject ]];
                [childContext af_refreshObjects:@[ managedObject ]];
                
            }];
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            
            NSLog(@"%s: %@, %@", __PRETTY_FUNCTION__, operation, error);
            
        }];
        
        [self.HTTPClient enqueueHTTPRequestOperation:operation];

    }

}

- (NSIncrementalStoreNode *) retrieveLocalValuesForObjectWithID:(NSManagedObjectID *)objectID context:(NSManagedObjectContext *)context error:(NSError **)error {

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:objectID.entity.name];
    fetchRequest.resultType = NSDictionaryResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesSubentities = NO;
    fetchRequest.propertiesToFetch = [[objectID.entity.attributesByName allKeys] arrayByAddingObject:kAFIncrementalStoreResourceIdentifierAttributeName];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", kAFIncrementalStoreResourceIdentifierAttributeName, [self referenceObjectForObjectID:objectID]];

    __block NSArray *results;
    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
    [backingContext af_performBlockAndWait:^{
        results = [backingContext executeFetchRequest:fetchRequest error:error];
    }];

    NSDictionary *attributeValues = [results lastObject] ?: [NSDictionary dictionary];
    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:attributeValues version:1];
    
    return node;

}

# pragma mark - Relationships

- (BOOL) shouldRetrieveRemoteValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context {

    if ([context af_ignoringCount])
        return NO;

    NSString *resourceIdentifier = [self referenceObjectForObjectID:objectID];
    if (!resourceIdentifier || (resourceIdentifier && ![resourceIdentifier isKindOfClass:[NSString class]]))
        return NO;
    
    AFHTTPClient<AFIncrementalStoreHTTPClient> *HTTPClient = self.HTTPClient;
    if (!HTTPClient)
        return NO;
    
    if (![HTTPClient respondsToSelector:@selector(shouldFetchRemoteValuesForRelationship:forObjectWithID:inManagedObjectContext:)])
        return NO;
    
    return [HTTPClient shouldFetchRemoteValuesForRelationship:relationship forObjectWithID:objectID inManagedObjectContext:context];

}

- (id) loadNewValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {
    
    NSEntityDescription *entity = objectID.entity;
    NSString *resourceIdentifier = [self referenceObjectForObjectID:objectID];
    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
    
    NSManagedObjectID *backingObjectID = [self backingObjectIDForEntity:entity resourceIdentifier:resourceIdentifier inContext:backingContext error:nil];
    
    NSManagedObject *backingObject = (backingObjectID == nil) ? nil : [backingContext existingObjectWithID:backingObjectID error:nil];
    
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

- (void) fetchNewValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context {
    
    NSCParameterAssert(relationship);
    NSCParameterAssert(objectID);
    NSCParameterAssert(context);
    
    if (![self shouldRetrieveRemoteValueForRelationship:relationship forObjectWithID:objectID withContext:context]) {
        return;
    }
    
    NSURLRequest *request = [self.HTTPClient requestWithMethod:@"GET" pathForRelationship:relationship forObjectWithID:objectID withContext:context];
    
    if (!request.URL)
        return;
    
    NSManagedObject *existingObject = [context existingObjectWithID:objectID error:nil];
    if (existingObject && [existingObject hasChanges])
        return;
    
    AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
    
        NSArray *representations = [self representationsFromResponseObject:responseObject];
        if (![representations count]) {
            return;
        }
        
        [self performUpdatesWithManagedContext:context backingContext:self.backingManagedObjectContext usingBlock:^(NSManagedObjectContext *childManagedContext, NSManagedObjectContext *childBackingContext) {
            
            [self importRepresentations:representations ofEntity:relationship.destinationEntity fromResponse:operation.response withManagedContext:childManagedContext backingContext:childBackingContext usingBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
                
                NSManagedObject *managedObject = [childManagedContext objectWithID:objectID];
                NSString *referenceObject = [self referenceObjectForObjectID:objectID];
                NSManagedObjectID *backingObjectID = [self backingObjectIDForEntity:objectID.entity resourceIdentifier:referenceObject inContext:childBackingContext error:nil];
                
                NSManagedObject *backingObject = [childBackingContext existingObjectWithID:backingObjectID error:nil];
                
                [managedObject af_setValue:managedObjects forRelationship:relationship];
                [backingObject af_setValue:backingObjects forRelationship:relationship];
                
                [childBackingContext af_saveObjects:backingObjects];
                [childBackingContext.parentContext af_performBlockAndWait:^{
                    [childBackingContext.parentContext save:nil];
                }];
                [childManagedContext af_refreshObjects:managedObjects];
                
            }];           
            
        }];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Error: %@, %@", operation, error);
        
    }];
    
    operation.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    operation.failureCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

    [self.HTTPClient enqueueHTTPRequestOperation:operation];

}

# pragma mark - Saving

- (BOOL) shouldExecuteRemoteSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context {

    return YES;

}

- (void) executeRemoteSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context {

    //  TBD: AFIncrementalStore should subclass NSOperation directly, or provide a async harness that invokes customer-provided blocks, and allow overriding methods that emit the blocks and blocks that call callback blocks.  Give all the save components a scratchpad to play on, and if everything finished, store everything in a batch.  A potential implementation will involve a change request tree that gets appended by each save operation (emitted by -operationsForSaveChangesRequest: operations).
    
    //  This is related to the Undo Management problem: the incremental store does asynchronous data fulfillment, so if the customer changed some more data and things do not go through, we can not even revert.

    NSArray *operations = [self operationsForSaveChangesRequest:saveChangesRequest];
    if ([operations count]) {
    
        [self notifyManagedObjectContext:context aboutRequestOperations:operations forSaveChangesRequest:saveChangesRequest];
        
        [self.HTTPClient enqueueBatchOfHTTPRequestOperations:operations progressBlock:^(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations) {
            
            //  ?
            
        } completionBlock:^(NSArray *operations) {
        
            [self notifyManagedObjectContext:context aboutRequestOperations:operations forSaveChangesRequest:saveChangesRequest];
            
        }];
    
    }

}

- (id) executeLocalSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    return @[];

}

- (NSArray *) operationsForSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest {
    
    NSMutableArray *ops = [NSMutableArray array];
    
    NSSet *insertedObjects = [saveChangesRequest insertedObjects];
    NSSet *updatedObjects = [saveChangesRequest updatedObjects];
    NSSet *deletedObjects = [saveChangesRequest deletedObjects];
    
    for (NSManagedObject *insertedObject in insertedObjects)
        [ops addObjectsFromArray:[self operationsForInsertedObject:insertedObject]];
    
    for (NSManagedObject *updatedObject in updatedObjects)
        [ops addObjectsFromArray:[self operationsForUpdatedObject:updatedObject]];

    for (NSManagedObject *deletedObject in deletedObjects)
        [ops addObjectsFromArray:[self operationsForDeletedObject:deletedObject]];
    
    return ops;
    
}

- (NSArray *) operationsForInsertedObject:(NSManagedObject *)insertedObject {

    AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
    
    if (![httpClient respondsToSelector:@selector(requestForInsertedObject:)])
        return @[];

    NSURLRequest *request = [httpClient requestForInsertedObject:insertedObject];
    if (!request)
        return @[];
    
    AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        NSEntityDescription *entity = insertedObject.entity;
        NSHTTPURLResponse *response = operation.response;
        
        NSString *resourceIdentifier = [self.HTTPClient resourceIdentifierForRepresentation:responseObject ofEntity:entity fromResponse:response];

        NSDictionary *attributes = [self.HTTPClient attributesForRepresentation:responseObject ofEntity:entity fromResponse:response];
        
        NSManagedObjectID *objectID = [self objectIDForEntity:[insertedObject entity] withResourceIdentifier:resourceIdentifier];
        insertedObject.af_resourceIdentifier = resourceIdentifier;
        [insertedObject setValuesForKeysWithDictionary:attributes];
        
        __block NSManagedObject *backingObject = nil;
        
        if (objectID) {
            [backingContext af_performBlockAndWait:^{
                backingObject = [backingContext existingObjectWithID:objectID error:nil];
            }];
        }
        
        if (!backingObject) {
            backingObject = [NSEntityDescription insertNewObjectForEntityForName:insertedObject.entity.name inManagedObjectContext:backingContext];
            [backingObject.managedObjectContext obtainPermanentIDsForObjects:@[ backingObject ] error:nil];
        }
        
        NSCParameterAssert(backingObject);
        NSCParameterAssert(backingObject.objectID);
        NSCParameterAssert(![backingObject.objectID isTemporaryID]);
        
        [backingObject setValue:resourceIdentifier forKey:kAFIncrementalStoreResourceIdentifierAttributeName];
        [backingObject setValuesForKeysWithDictionary:attributes];
        
        [self updateRelationshipsOfBackingObject:backingObject withRelationshipsOfManagedObject:insertedObject];
                        
        [self obtainPermanentIDForTemporaryObject:insertedObject withResourceIdentifier:resourceIdentifier];
        
        [self assertManagedObject:insertedObject hasAssociationsEquivalentToBackingObject:backingObject];
        
        [self performUpdatesWithManagedContext:insertedObject.managedObjectContext backingContext:self.backingManagedObjectContext usingBlock:^(NSManagedObjectContext *childManagedContext, NSManagedObjectContext *childBackingContext) {
            
            [self importRepresentations:@[ responseObject ] ofEntity:entity fromResponse:operation.response withManagedContext:childManagedContext backingContext:childBackingContext usingBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
                
                NSCParameterAssert([managedObjects count] == 1);
                NSCParameterAssert([backingObjects count] == 1);
                
                [childBackingContext af_saveObjects:backingObjects];
                [childBackingContext.parentContext af_performBlockAndWait:^{
                    [childBackingContext.parentContext save:nil];
                }];
                [childManagedContext af_refreshObjects:managedObjects];
                
            }];
            
        }];
                        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Insert Error: %@", error);
        
    }];
    
    return @[ operation ];

}

- (NSArray *) operationsForUpdatedObject:(NSManagedObject *)updatedObject {

    AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
    
    if (![httpClient respondsToSelector:@selector(requestForUpdatedObject:)])
        return @[];
    
    NSURLRequest *request = [httpClient requestForUpdatedObject:updatedObject];
    if (!request)
        return nil;
    
    AFHTTPRequestOperation *operation = [httpClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
    
        [updatedObject setValuesForKeysWithDictionary:[httpClient attributesForRepresentation:responseObject ofEntity:updatedObject.entity fromResponse:operation.response]];
        
        [backingContext af_performBlockAndWait:^{
            NSManagedObject *backingObject = [backingContext existingObjectWithID:updatedObject.objectID error:nil];
            [backingObject setValuesForKeysWithDictionary:[updatedObject dictionaryWithValuesForKeys:nil]];
            [backingContext save:nil];
        }];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Update Error: %@", error);
        
    }];
    
    return @[ operation ];

}

- (NSArray *) operationsForDeletedObject:(NSManagedObject *)deletedObject {

    AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
    NSManagedObjectContext *backingContext = self.backingManagedObjectContext;
    
    if (![self.HTTPClient respondsToSelector:@selector(requestForDeletedObject:)])
        return @[];
    
    NSURLRequest *request = [httpClient requestForDeletedObject:deletedObject];
    if (!request)
        return nil;
    
    AFHTTPRequestOperation *operation = [self.HTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
    
        [backingContext af_performBlockAndWait:^{
            
            NSManagedObject *backingObject = [backingContext existingObjectWithID:deletedObject.objectID error:nil];
            [backingContext deleteObject:backingObject];
            [backingContext save:nil];
            
        }];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"Delete Error: %@", error);
        
    }];
    
    return @[ operation ];

}

# pragma mark - Updates

- (void) performUpdatesWithManagedContext:(NSManagedObjectContext *)managedContext backingContext:(NSManagedObjectContext *)backingContext usingBlock:(void(^)(NSManagedObjectContext *childManagedContext, NSManagedObjectContext *childBackingContext))block {
    
    NSCParameterAssert(managedContext);
    NSCParameterAssert(managedContext.persistentStoreCoordinator == self.persistentStoreCoordinator);
    NSCParameterAssert(backingContext);
    NSCParameterAssert(backingContext.persistentStoreCoordinator == self.backingPersistentStoreCoordinator);
    NSCParameterAssert(block);
    
    __weak typeof(managedContext) wManagedContext = managedContext;
    __weak typeof(backingContext) wBackingContext = backingContext;
    
    [self.operationQueue addOperation:[self newAsyncOperationWithWorker:^(RAAsyncOperationCallback callback) {
        
        if (!wManagedContext || !wBackingContext) {
            callback((id)kCFBooleanFalse);
            return;
        }
        
        NSManagedObjectContext *childManagedContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
        childManagedContext.parentContext = wManagedContext;
        childManagedContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
        
        NSManagedObjectContext *childBackingContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
        childBackingContext.parentContext = wBackingContext;
        childBackingContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
        
        block(childManagedContext, childBackingContext);
        callback((id)kCFBooleanTrue);

    } callback:nil]];
    
}

- (void) updateRelationshipsOfBackingObject:(NSManagedObject *)backingObject withRelationshipsOfManagedObject:(NSManagedObject *)insertedObject {
    
    NSManagedObjectContext *backingContext = backingObject.managedObjectContext;
    
    [[insertedObject.entity relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription *relationship, BOOL *stop) {
    
        id requestedRelationship = [insertedObject valueForKey:name];
        if (!requestedRelationship)
            return;
        
        id providedRelationship = nil;
        
        NSManagedObject * (^backingObjectForManagedObject)(NSManagedObject *) = ^ (NSManagedObject *incomingObject) {
        
            return [self backingObjectInContext:backingContext forManagedObject:incomingObject];
        
        };
        
        if ([relationship isToMany]) {
        
            if ([relationship isOrdered]) {
            
                providedRelationship = [NSMutableOrderedSet orderedSet];
                for (NSManagedObject *relationshipObject in (NSOrderedSet *)requestedRelationship) {
                    NSManagedObject *relatedObject = backingObjectForManagedObject(relationshipObject);
                    if (relatedObject) {
                        [(NSMutableOrderedSet *)providedRelationship addObject:relatedObject];
                    } else {
                        NSLog(@"%s: lost track of relationship object %@", __PRETTY_FUNCTION__, relationshipObject);
                    }
                }
            
            } else {
            
                providedRelationship = [NSMutableSet set];
                for (NSManagedObject *relationshipObject in (NSSet *)requestedRelationship) {
                    NSManagedObject *relatedObject = backingObjectForManagedObject(relationshipObject);
                    if (relatedObject) {
                        [(NSMutableSet *)providedRelationship addObject:relatedObject];
                    } else {
                        NSLog(@"%s: lost track of relationship object %@", __PRETTY_FUNCTION__, relationshipObject);
                    }
                }
                
            }
        
        } else {
        
            NSManagedObject *relationshipObject = (NSManagedObject *)requestedRelationship;
            NSManagedObject *relatedObject = backingObjectForManagedObject(relationshipObject);
            if (relatedObject) {
                providedRelationship = relatedObject;
            } else {
                NSLog(@"%s: lost track of relationship object %@", __PRETTY_FUNCTION__, relationshipObject);
            }
        
        }
        
        [backingObject setValue:providedRelationship forKey:name];
        
    }];

}

# pragma mark - Object Identity

- (NSArray *) obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error {
    
    NSMutableArray *mutablePermanentIDs = [NSMutableArray arrayWithCapacity:[array count]];
    for (NSManagedObject *managedObject in array) {
        NSManagedObjectID *managedObjectID = managedObject.objectID;
        if ([managedObjectID isTemporaryID] && managedObject.af_resourceIdentifier) {
            NSManagedObjectID *objectID = [self objectIDForEntity:managedObject.entity withResourceIdentifier:managedObject.af_resourceIdentifier];
            [mutablePermanentIDs addObject:objectID];
        } else {
            [mutablePermanentIDs addObject:managedObjectID];
        }
    }
    
    return mutablePermanentIDs;
    
}

- (void) obtainPermanentIDForTemporaryObject:(NSManagedObject *)object withResourceIdentifier:(NSString *)resourceIdentifier {
    
    NSCParameterAssert(![object af_isPermanent]);
    
    object.af_resourceIdentifier = resourceIdentifier;
    
    [object willChangeValueForKey:@"objectID"];
    
    NSError *permanentIDsObtainingError = nil;
    BOOL didObtainPermanentIDs = [object.managedObjectContext obtainPermanentIDsForObjects:[NSArray arrayWithObject:object] error:&permanentIDsObtainingError];
    
    if (!didObtainPermanentIDs)
        NSLog(@"%s: %@", __PRETTY_FUNCTION__, permanentIDsObtainingError);

    [object didChangeValueForKey:@"objectID"];
    
    NSCParameterAssert([object af_isPermanent]);

}

- (void) managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs {

    [super managedObjectContextDidRegisterObjectsWithIDs:objectIDs];
    
    for (NSManagedObjectID *objectID in objectIDs) {
        
        id key = [self referenceObjectForObjectID:objectID];
        NSString *entityName = objectID.entity.name;
        NSMutableDictionary *objectIDsByResourceIdentifier = _registeredObjectIDsByResourceIdentifier[entityName];
        if (!objectIDsByResourceIdentifier) {
            objectIDsByResourceIdentifier = [NSMutableDictionary dictionary];
            _registeredObjectIDsByResourceIdentifier[entityName] = objectIDsByResourceIdentifier;
        }
        
        objectIDsByResourceIdentifier[key] = objectID;
        
    }
    
}

- (void) managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs {
    
    [super managedObjectContextDidUnregisterObjectsWithIDs:objectIDs];
    
    for (NSManagedObjectID *objectID in objectIDs) {
        
        id key = [self referenceObjectForObjectID:objectID];
        NSString *entityName = objectID.entity.name;
        
        [_registeredObjectIDsByResourceIdentifier[entityName] removeObjectForKey:key];
        
    }
    
}

- (NSManagedObjectID *) objectIDForEntity:(NSEntityDescription *)entity withResourceIdentifier:(NSString *)resourceIdentifier {
    
    if (!resourceIdentifier)
        return nil;
    
    NSManagedObjectID *objectID = _registeredObjectIDsByResourceIdentifier[entity.name][resourceIdentifier];
    if (!objectID) {
        objectID = [self newObjectIDForEntity:entity referenceObject:resourceIdentifier];
    }
    
    NSCParameterAssert(objectID);
    NSCParameterAssert([objectID.entity.name isEqualToString:entity.name]);
    return objectID;
    
}

- (NSFetchRequest *) fetchRequestForObjectIDWithEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)resourceID {

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:entity.name];
    fetchRequest.resultType = NSManagedObjectIDResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", kAFIncrementalStoreResourceIdentifierAttributeName, resourceID];

    return fetchRequest;

}

#pragma mark - Notifications

- (void) notifyManagedObjectContext:(NSManagedObjectContext *)context aboutRequestOperation:(AFHTTPRequestOperation *)operation forFetchRequest:(NSFetchRequest *)fetchRequest {
    
    NSString *notificationName = [operation isFinished] ?
        AFIncrementalStoreContextDidFetchRemoteValues :
        AFIncrementalStoreContextWillFetchRemoteValues;

    NSDictionary *userInfo = @{
        AFIncrementalStoreRequestOperationKey: operation,
        AFIncrementalStorePersistentStoreRequestKey: fetchRequest
    };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:context userInfo:userInfo];
        
    });

}

- (void)notifyManagedObjectContext:(NSManagedObjectContext *)context
            aboutRequestOperations:(NSArray *)operations
             forSaveChangesRequest:(NSSaveChangesRequest *)saveChangesRequest
{
    NSString *notificationName = [[operations lastObject] isFinished] ? AFIncrementalStoreContextDidSaveRemoteValues : AFIncrementalStoreContextWillSaveRemoteValues;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:operations forKey:AFIncrementalStoreRequestOperationKey];
    [userInfo setObject:saveChangesRequest forKey:AFIncrementalStorePersistentStoreRequestKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:context userInfo:userInfo];
}

# pragma mark - Importing

- (void) importRepresentations:(id)representationOrArrayOfRepresentations ofEntity:(NSEntityDescription *)entity fromResponse:(NSHTTPURLResponse *)response withManagedContext:(NSManagedObjectContext *)managedContext backingContext:(NSManagedObjectContext *)backingContext usingBlock:(void (^)(NSArray *managedObjects, NSArray *backingObjects))completionBlock {
    
    NSCParameterAssert(representationOrArrayOfRepresentations);
    NSCParameterAssert(entity);
    NSCParameterAssert(response);
    NSCParameterAssert(managedContext);
    NSCParameterAssert(managedContext.persistentStoreCoordinator == self.persistentStoreCoordinator);
    NSCParameterAssert(managedContext.concurrencyType == NSConfinementConcurrencyType);
    NSCParameterAssert(backingContext);
    NSCParameterAssert(backingContext.persistentStoreCoordinator == self.backingPersistentStoreCoordinator);
    NSCParameterAssert(backingContext.concurrencyType == NSConfinementConcurrencyType);
    NSCParameterAssert(completionBlock);
    
    NSDate *lastModified = [self lastModifiedDateFromHTTPHeaders:[response allHeaderFields]];
    
    NSArray *representations = [self representationsFromResponseObject:representationOrArrayOfRepresentations];
    NSCParameterAssert(representations);
    if (![representations count]) {
        if (completionBlock) {
            completionBlock(nil, nil);
        }
        return;
    }

    NSUInteger numberOfRepresentations = [representations count];
    NSMutableArray *mutableManagedObjects = [NSMutableArray arrayWithCapacity:numberOfRepresentations];
    NSMutableArray *mutableBackingObjects = [NSMutableArray arrayWithCapacity:numberOfRepresentations];
    
    for (NSDictionary *representation in representations) {
        
        NSString *resourceIdentifier = [self.HTTPClient resourceIdentifierForRepresentation:representation ofEntity:entity fromResponse:response];
        NSDictionary *attributes = [self.HTTPClient attributesForRepresentation:representation ofEntity:entity fromResponse:response];
        
        __block NSManagedObject *managedObject;
        [managedContext af_performBlockAndWait:^{
            managedObject = [managedContext existingObjectWithID:[self objectIDForEntity:entity withResourceIdentifier:resourceIdentifier] error:nil];
        }];

        [managedObject setValuesForKeysWithDictionary:attributes];
        
        NSManagedObjectID *backingObjectID = [self backingObjectIDForEntity:entity resourceIdentifier:resourceIdentifier inContext:backingContext error:nil];
        
        __block NSManagedObject *backingObject;
        [backingContext af_performBlockAndWait:^{
            if (backingObjectID) {
                backingObject = [backingContext existingObjectWithID:backingObjectID error:nil];
            } else {
                backingObject = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:backingContext];
                [backingObject.managedObjectContext obtainPermanentIDsForObjects:@[ backingObject ] error:nil];
            }
        }];
        [backingObject setValue:resourceIdentifier forKey:kAFIncrementalStoreResourceIdentifierAttributeName];
        [backingObject setValue:lastModified forKey:kAFIncrementalStoreLastModifiedAttributeName];
        [backingObject setValuesForKeysWithDictionary:attributes];
        
        if (!backingObjectID) {
            [managedContext insertObject:managedObject];
        }
        
        NSDictionary *relationshipRepresentations = [self.HTTPClient representationsForRelationshipsFromRepresentation:representation ofEntity:entity fromResponse:response];
        for (NSString *relationshipName in relationshipRepresentations) {
            
            NSRelationshipDescription *relationship = [[entity relationshipsByName] valueForKey:relationshipName];
            if (!relationship)
                continue;
            
            id relationshipRepresentation = [relationshipRepresentations objectForKey:relationshipName];
            
            if (!relationshipRepresentation || [relationshipRepresentation isEqual:[NSNull null]] || ![relationshipRepresentation count]) {
                [managedObject setValue:nil forKey:relationshipName];
                [backingObject setValue:nil forKey:relationshipName];
                continue;
            }
            
            [self importRepresentations:relationshipRepresentation ofEntity:relationship.destinationEntity fromResponse:response withManagedContext:managedContext backingContext:backingContext usingBlock:^(NSArray *managedObjects, NSArray *backingObjects) {
                
                [managedObject af_setValue:managedObjects forRelationship:relationship];
                [backingObject af_setValue:backingObjects forRelationship:relationship];
                
            }];
        }
        
        [mutableManagedObjects addObject:managedObject];
        [mutableBackingObjects addObject:backingObject];
    }
    
    if (completionBlock) {
        completionBlock(mutableManagedObjects, mutableBackingObjects);
    }
    
}

- (NSArray *) representationsFromResponseObject:(id)responseObject {

    id representationOrArrayOfRepresentations = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:responseObject];
    
    if ([representationOrArrayOfRepresentations isKindOfClass:[NSArray class]])
        return representationOrArrayOfRepresentations;
    
    if ([representationOrArrayOfRepresentations isKindOfClass:[NSDictionary class]])
        return @[ representationOrArrayOfRepresentations ];
    
    return nil;
    
}

# pragma mark - Safety

- (void) assertManagedObject:(NSManagedObject *)managedObject hasAssociationsEquivalentToBackingObject:(NSManagedObject *)backingObject {

    NSDictionary *backingRelationships = backingObject.entity.relationshipsByName;
    NSDictionary *managedRelationships = managedObject.entity.relationshipsByName;
    NSCParameterAssert([backingRelationships count] == [managedRelationships count]);
    NSCParameterAssert([[backingRelationships allKeys] isEqualToArray:[managedRelationships allKeys]]);
    [backingRelationships enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSRelationshipDescription*backingRelationship, BOOL *stop) {
        if ([backingObject valueForKey:name]) {
            NSCParameterAssert([managedObject valueForKey:name]);
        } else {
            NSCParameterAssert(![managedObject valueForKey:name]);
        }
    }];

}

# pragma mark - Concurrency

- (NSOperationQueue *) operationQueue {

    if (!_operationQueue) {
    
        _operationQueue = [RAOperationQueue new];
        _operationQueue.maxConcurrentOperationCount = 1;
    
    }
    
    return _operationQueue;

}

- (dispatch_queue_t) dispatchQueue {

    if (!_dispatchQueue) {
        
        _dispatchQueue = dispatch_queue_create([NSStringFromClass([self class]) UTF8String], DISPATCH_QUEUE_SERIAL);
    
    }
    
    return _dispatchQueue;

}

- (RAAsyncOperation *) newAsyncOperationWithWorker:(RAAsyncOperationWorker)workerBlock callback:(RAAsyncOperationCallback)callbackBlock {
    
    return [RAAsyncOperation operationWithWorker:workerBlock trampoline:^(IRAsyncOperationInvoker callback) {
        
        dispatch_async(self.dispatchQueue, callback);
        
    } callback:callbackBlock trampoline:^(IRAsyncOperationInvoker callback) {
        
        dispatch_async(self.dispatchQueue, callback);
        
    }];
    
}

# pragma mark - Utilities

- (NSDate *) lastModifiedDateFromHTTPHeaders:(NSDictionary *)headers {
    
    if (![headers valueForKey:@"Last-Modified"])
        return nil;

    static dispatch_once_t onceToken;
    static ISO8601DateFormatter *dateFormatter = nil;
    dispatch_once(&onceToken, ^{
        dateFormatter = [ISO8601DateFormatter new];
    });
    
    return [dateFormatter dateFromString:[headers valueForKey:@"last-modified"]];
    
}

@end
