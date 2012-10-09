//  AFIncrementalStore+ObjectIDs.m

#import <objc/runtime.h>
#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStoreReferenceObject.h"

NSString * kAFIncrementalStoreObjectIDContext = @"AFIncrementalStoreObjectIDContext";

@implementation AFIncrementalStore (ObjectIDs)

- (NSManagedObjectID *)objectIDForEntity:(NSEntityDescription *)entity
                  withResourceIdentifier:(NSString *)resourceIdentifier {
  
	AFIncrementalStoreReferenceObject *referenceObject = [AFIncrementalStoreReferenceObject objectWithEntity:entity resourceIdentifier:resourceIdentifier];

	NSManagedObjectID *objectID = [_registeredObjectIDsByResourceIdentifier objectForKey:referenceObject];
	
	if (!objectID) {
		objectID = [self newObjectIDForEntity:entity referenceObject:resourceIdentifier];
		objc_setAssociatedObject(objectID, &kAFIncrementalStoreObjectIDContext, referenceObject, OBJC_ASSOCIATION_RETAIN);
	}
	
	NSCParameterAssert([objectID persistentStore] == self);
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
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K = %@", AFIncrementalStoreResourceIdentifierAttributeName, resourceIdentifier];
    
    NSError *error = nil;
    NSArray *results = [[self backingManagedObjectContext] executeFetchRequest:fetchRequest error:&error];
    if (error) {
        NSLog(@"Error: %@", error);
        return nil;
    }
    
    return [results lastObject];
}

- (NSManagedObjectID *) newObjectIDForEntity:(NSEntityDescription *)entity resourceIdentifier:(NSString *)resourceIdentifier {

	AFIncrementalStoreReferenceObject *referenceObject = [AFIncrementalStoreReferenceObject objectWithEntity:entity resourceIdentifier:resourceIdentifier];
	
	NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:resourceIdentifier];
	objc_setAssociatedObject(objectID, &kAFIncrementalStoreObjectIDContext, referenceObject, OBJC_ASSOCIATION_RETAIN);
	
	return objectID;

}

- (NSString *) resourceIdentifierForObjectID:(NSManagedObjectID *)objectID {

	id referenceObject = objc_getAssociatedObject(objectID, &kAFIncrementalStoreObjectIDContext);
	
	if ([referenceObject isKindOfClass:[AFIncrementalStoreReferenceObject class]]) {
		return [(AFIncrementalStoreReferenceObject *)referenceObject resourceIdentifier];
	}
	
	return nil;

}

@end
