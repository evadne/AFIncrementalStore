//  AFIncrementalStore+ObjectIDs.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStoreReferenceObject.h"

@implementation AFIncrementalStore (ObjectIDs)

- (NSManagedObjectID *)objectIDForEntity:(NSEntityDescription *)entity
                  withResourceIdentifier:(NSString *)resourceIdentifier {
  
	AFIncrementalStoreReferenceObject *referenceObject = [AFIncrementalStoreReferenceObject objectWithEntity:entity resourceIdentifier:resourceIdentifier];

	NSManagedObjectID *registeredObjectID = [_registeredObjectIDsByResourceIdentifier objectForKey:referenceObject];
	
	if (!registeredObjectID)
		return [self newObjectIDForEntity:entity referenceObject:referenceObject];
	
	NSCParameterAssert([registeredObjectID persistentStore] == self);
	
	return registeredObjectID;
	
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
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", AFIncrementalStoreResourceIdentifierAttributeName, resourceIdentifier];
    
    NSError *error = nil;
    NSArray *results = [[self backingManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
    if (error) {
        NSLog(@"Error: %@", error);
        return nil;
    }
    
    return [results lastObject];
}

- (NSManagedObjectID *) newObjectIDForEntity:(NSEntityDescription *)entity referenceObject:(AFIncrementalStoreReferenceObject *)data {

	if ([data isKindOfClass:[AFIncrementalStoreReferenceObject class]]) {
	
		return [super newObjectIDForEntity:entity referenceObject:data];
		
	} else {
	
		AFIncrementalStoreReferenceObject *referneceObject = [AFIncrementalStoreReferenceObject objectWithEntity:entity resourceIdentifier:nil];
		
		return [super newObjectIDForEntity:entity referenceObject:referneceObject];
		
	}
	
}

- (AFIncrementalStoreReferenceObject *) referenceObjectForObjectID:(NSManagedObjectID *)objectID {

	id object = [super referenceObjectForObjectID:objectID];
	NSCParameterAssert(!object || [object isKindOfClass:[AFIncrementalStoreReferenceObject class]]);
	
	return object;

}

@end
