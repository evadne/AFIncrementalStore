//  AFIncrementalStore+BackingStore.h

#import "AFIncrementalStore.h"

@interface AFIncrementalStore (BackingStore)

- (NSManagedObjectModel *) backingManagedObjectModel;
- (NSManagedObjectContext *) backingManagedObjectContext;

@end
