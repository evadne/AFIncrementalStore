//  AFIncrementalStore+Faulting.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Faulting.h"
#import "AFIncrementalStore+Notifications.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStoreReferenceObject.h"

@implementation AFIncrementalStore (Faulting)

- (NSIncrementalStoreNode *) newValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError *__autoreleasing *)error {

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:[[objectID entity] name]];
    fetchRequest.resultType = NSDictionaryResultType;
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesSubentities = NO;
    fetchRequest.propertiesToFetch = [[[NSEntityDescription entityForName:fetchRequest.entityName inManagedObjectContext:context] attributesByName] allKeys];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", AFIncrementalStoreResourceIdentifierAttributeName, [self referenceObjectForObjectID:objectID].resourceIdentifier];
    
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

@end
