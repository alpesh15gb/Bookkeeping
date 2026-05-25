import inspect
from typing import Any, Callable, Dict, List, Type
import logging

logger = logging.getLogger(__name__)

class DomainEvent:
    """Base class for all domain events in the system."""
    pass

class EventDispatcher:
    """
    Synchronous In-Memory Event Dispatcher.
    Enables components to publish and subscribe to domain events without hard coupling.
    """
    def __init__(self):
        self._listeners: Dict[Type[DomainEvent], List[Callable[[Any], None]]] = {}

    def subscribe(self, event_type: Type[DomainEvent], handler: Callable[[Any], None]) -> None:
        """Subscribes a handler to a specific event type."""
        if event_type not in self._listeners:
            self._listeners[event_type] = []
        self._listeners[event_type].append(handler)
        logger.debug(f"Registered subscriber {handler.__name__} for event {event_type.__name__}")

    def unsubscribe(self, event_type: Type[DomainEvent], handler: Callable[[Any], None]) -> None:
        """Removes a handler from the event type subscriber list."""
        if event_type in self._listeners:
            try:
                self._listeners[event_type].remove(handler)
                logger.debug(f"Unsubscribed {handler.__name__} from event {event_type.__name__}")
            except ValueError:
                pass

    def publish(self, event: DomainEvent) -> None:
        """Dispatches the event to all registered subscribers."""
        event_type = type(event)
        if event_type not in self._listeners:
            logger.debug(f"No subscribers registered for event: {event_type.__name__}")
            return

        for handler in self._listeners[event_type]:
            try:
                if inspect.iscoroutinefunction(handler):
                    # If handler is async, log warning or raise error (since dispatcher is sync)
                    raise RuntimeError(f"Sync EventDispatcher cannot execute async handler {handler.__name__}")
                handler(event)
            except Exception as e:
                # Event dispatch failures should not roll back the entire transaction unless explicitly desired,
                # but we log them as critical errors.
                logger.critical(
                    f"Error executing handler {handler.__name__} for event {event_type.__name__}: {str(e)}",
                    exc_info=True
                )

# Global Instance for application-wide domain event routing
dispatcher = EventDispatcher()
