//  AFIncrementalStore+Importing.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (Importing)

- (NSManagedObject *) insertOrUpdateObjectWithEntity:(NSEntityDescription *)entity attributes:(NSDictionary *)attributes resourceIdentifier:(NSString *)resourceIdentifier inContext:(NSManagedObjectContext *)context;

- (void) importRepresentation:(NSDictionary *)representation ofEntity:(NSEntityDescription *)entity withResponse:(NSHTTPURLResponse *)response context:(NSManagedObjectContext *)childContext asManagedObject:(NSManagedObject **)outManagedObject backingObject:(NSManagedObject **)outBackingObject;

- (NSArray *) representationsFromResponse:(NSHTTPURLResponse *)response;

@end
