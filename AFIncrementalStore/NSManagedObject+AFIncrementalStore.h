#import <CoreData/CoreData.h>

@interface NSManagedObject (AFIncrementalStore)

@property (readwrite, nonatomic, copy, setter = af_setResourceIdentifier:) NSString *af_resourceIdentifier;

- (BOOL) af_isPermanent;

- (void) af_setValue:(id)value forRelationship:(NSRelationshipDescription *)relationship;

@end
