//  AFIncrementalStore+BackingStore.m

#import "AFIncrementalStore+BackingStore.h"

@implementation AFIncrementalStore (BackingStore)

- (NSManagedObjectModel *) backingManagedObjectModel {

	NSManagedObjectModel *model = self.persistentStoreCoordinator.managedObjectModel;
	NSManagedObjectModel *backingModel = [model copy];
	
	for (NSEntityDescription *entity in backingModel.entities) {

		// Don't add resource identifier property for sub-entities, as they already exist in the super-entity
		
		if (![entity superentity]) {

			NSAttributeDescription *resourceIdentifierProperty = [[NSAttributeDescription alloc] init];
			[resourceIdentifierProperty setName:AFIncrementalStoreResourceIdentifierAttributeName];
			[resourceIdentifierProperty setAttributeType:NSStringAttributeType];
			[resourceIdentifierProperty setIndexed:YES];
			
			[entity setProperties:[entity.properties arrayByAddingObject:resourceIdentifierProperty]];
		
		}
	
	}
		
	return backingModel;

}

- (NSPersistentStoreCoordinator *) backingPersistentStoreCoordinator {

	if (!_backingPersistentStoreCoordinator) {
	
		NSManagedObjectModel *model = [self backingManagedObjectModel];
	
		_backingPersistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	
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

@end
