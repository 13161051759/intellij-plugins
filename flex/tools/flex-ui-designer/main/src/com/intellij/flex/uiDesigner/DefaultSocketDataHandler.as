package com.intellij.flex.uiDesigner {
import cocoa.ClassFactory;
import cocoa.DocumentWindow;
import cocoa.pane.PaneItem;
import cocoa.toolWindow.ToolWindowManager;

import com.intellij.flex.uiDesigner.css.LocalStyleHolder;
import com.intellij.flex.uiDesigner.io.AmfUtil;
import com.intellij.flex.uiDesigner.libraries.FlexLibrarySet;
import com.intellij.flex.uiDesigner.libraries.LibraryManager;
import com.intellij.flex.uiDesigner.libraries.LibrarySet;
import com.intellij.flex.uiDesigner.ui.ProjectEventMap;
import com.intellij.flex.uiDesigner.ui.ProjectView;
import com.intellij.flex.uiDesigner.ui.inspectors.propertyInspector.PropertyInspector;

import flash.geom.Rectangle;
import flash.net.Socket;
import flash.net.registerClassAlias;
import flash.utils.ByteArray;
import flash.utils.IDataInput;
import flash.utils.describeType;

import net.miginfocom.layout.MigConstants;

import org.jetbrains.ApplicationManager;

registerClassAlias("lsh", LocalStyleHolder);

// SocketDataHandler is extension component (i.e. DefaultSocketDataHandler as role, lookup must be container.lookup(DefaultSocketDataHandler))
internal class DefaultSocketDataHandler implements SocketDataHandler {
  private var projectManager:ProjectManager;
  private var libraryManager:LibraryManager;
  private var moduleManager:ModuleManager;
  private var stringRegistry:StringRegistry;

  public function DefaultSocketDataHandler(libraryManager:LibraryManager, projectManager:ProjectManager, moduleManager:ModuleManager, stringRegistry:StringRegistry) {
    this.libraryManager = libraryManager;
    this.projectManager = projectManager;
    this.moduleManager = moduleManager;
    this.stringRegistry = stringRegistry;
  }

  public function set socket(value:Socket):void {
  }

  public function handleSockedData(messageSize:int, method:int, input:IDataInput):void {
    switch (method) {
      case ClientMethod.openProject:
        openProject(input);
        break;
      
      case ClientMethod.closeProject:
        projectManager.close(input.readUnsignedShort());
        break;

      case ClientMethod.registerLibrarySet:
        registerLibrarySet(input);
        break;

      case ClientMethod.registerModule:
        registerModule(input);
        break;
      
      case ClientMethod.registerDocumentFactory:
        registerDocumentFactory(input, messageSize);
        break;
      
      case ClientMethod.updateDocumentFactory:
        updateDocumentFactory(input, messageSize);
        break;

      case ClientMethod.openDocument:
        openDocument(input);
        break;
      
      case ClientMethod.updateDocuments:
        updateDocuments(input);
        break;
      
      case ClientMethod.initStringRegistry:
        stringRegistry.initStringTable(input);
        break;

      case ClientMethod.updateStringRegistry:
        stringRegistry.readStringTable(input);
        break;

      case ClientMethod.fillImageClassPool:
        fillAssetClassPool(input, messageSize, false);
        break;

      case ClientMethod.fillSwfClassPool:
        fillAssetClassPool(input, messageSize, true);
        break;
    }
  }

  private function fillAssetClassPool(input:IDataInput, messageSize:int, isSwf:Boolean):void {
    const prevBytesAvailable:int = input.bytesAvailable;
    var librarySet:FlexLibrarySet = FlexLibrarySet(libraryManager.getById(input.readUnsignedShort()));
    const classCount:int = input.readUnsignedShort();
    var swfData:ByteArray = new ByteArray();
    input.readBytes(swfData, 0, messageSize - (prevBytesAvailable - input.bytesAvailable));
    (isSwf ? librarySet.swfAssetContainerClassPool : librarySet.imageAssetContainerClassPool).fill(classCount, swfData, librarySet, libraryManager);
  }

  private function openProject(input:IDataInput):void {
    var project:Project = new Project(input.readUnsignedShort(), AmfUtil.readString(input), new ProjectEventMap());
    var projectWindowBounds:Rectangle;
    if (input.readBoolean()) {
      projectWindowBounds = new Rectangle(input.readUnsignedShort(), input.readUnsignedShort(), input.readUnsignedShort(), input.readUnsignedShort());
    }
    var projectView:ProjectView = new ProjectView();
    projectView.laf = ApplicationManager.instance.laf;
    var documentWindow:DocumentWindow = new DocumentWindow(projectView, new MainFocusManager());
    projectManager.open(project, documentWindow);

    var toolWindowManager:ToolWindowManager = ToolWindowManager(project.getComponent(ToolWindowManager));
    toolWindowManager.container = projectView;
    toolWindowManager.registerToolWindow(PaneItem.create("Style", new ClassFactory(PropertyInspector)), MigConstants.RIGHT);

    documentWindow.init(project.map, projectWindowBounds);
  }

  private function registerModule(input:IDataInput):void {
    stringRegistry.readStringTable(input);
    var module:Module = new Module(input.readUnsignedShort(), projectManager.getById(input.readUnsignedShort()), input.readBoolean(),
                                   libraryManager.idsToInstances(input.readObject()), input.readObject());
    moduleManager.register(module);
  }

  private function registerDocumentFactory(input:IDataInput, messageSize:int):void {
    const prevBytesAvailable:int = input.bytesAvailable;
    var module:Module = moduleManager.getById(input.readUnsignedShort());
    var bytes:ByteArray = new ByteArray();
    var documentFactory:DocumentFactory = new DocumentFactory(input.readUnsignedShort(), bytes, VirtualFileImpl.create(input),
                                                              AmfUtil.readString(input), input.readUnsignedByte(), module);

    if (input.readBoolean()) {
      documentFactory.documentReferences = input.readObject();
    }
    getDocumentFactoryManager().register(documentFactory);

    stringRegistry.readStringTable(input);
    input.readBytes(bytes, 0, messageSize - (prevBytesAvailable - input.bytesAvailable));
  }
  
  private function updateDocumentFactory(input:IDataInput, messageSize:int):void {
    const prevBytesAvailable:int = input.bytesAvailable;
    var documentFactory:DocumentFactory = getDocumentFactoryManager().get(input.readUnsignedShort());
    AmfUtil.readString(input);
    input.readUnsignedByte(); // todo isApp update document styleManager

    if (input.readBoolean()) {
      documentFactory.documentReferences = input.readObject();
    }
    
    stringRegistry.readStringTable(input);

    const length:int = messageSize - (prevBytesAvailable - input.bytesAvailable);
    var bytes:ByteArray = documentFactory.data;
    bytes.position = 0;
    bytes.length = length;
    input.readBytes(bytes, 0, length);
  }

  private static function getDocumentFactoryManager():DocumentFactoryManager {
    return DocumentFactoryManager.getInstance();
  }
  
  private static function getDocumentManager(module:Module):DocumentManager {
    return DocumentManager(module.project.getComponent(DocumentManager));
  }

  private function openDocument(input:IDataInput):void {
    var module:Module = moduleManager.getById(input.readUnsignedShort());
    var documentFactory:DocumentFactory = getDocumentFactoryManager().get(input.readUnsignedShort());

    var documentOpened:Function;
    if (input.readBoolean()) {
      documentOpened = Server.instance.documentOpened;
    }

    getDocumentManager(module).open(documentFactory, documentOpened);
  }
  
  private function updateDocuments(input:IDataInput):void {
    var module:Module = moduleManager.getById(input.readUnsignedShort());
    var documentFactoryManager:DocumentFactoryManager = getDocumentFactoryManager();
    var documentFactory:DocumentFactory = documentFactoryManager.get(input.readUnsignedShort());
    var documentManager:DocumentManager = getDocumentManager(module);
    // not set projectManager.project — current project is not changed (opposite to openDocument)
    openDocumentsForFactory(documentFactory, documentManager, documentFactoryManager);
  }

  private static function openDocumentsForFactory(documentFactory:DocumentFactory, documentManager:DocumentManager,
                                                  documentFactoryManager:DocumentFactoryManager):void {
    if (documentFactory.document != null) {
      documentManager.open(documentFactory);
    }

    if (documentFactory.documentReferences != null) {
      for each (var id:int in documentFactory.documentReferences) {
        openDocumentsForFactory(documentFactoryManager.get(id), documentManager, documentFactoryManager);
      }
    }
  }

  private function registerLibrarySet(data:IDataInput):void {
    const id:int = AmfUtil.readUInt29(data);
    const isFlexLibrarySet:Boolean = data.readBoolean();
    var parentId:int = data.readShort();
    var parent:LibrarySet = parentId == -1 ? null : libraryManager.getById(parentId);
    var librarySet:LibrarySet = isFlexLibrarySet ? new FlexLibrarySet(id, parent) : new LibrarySet(id, parent);
    librarySet.readExternal(data);
    libraryManager.register(librarySet);
  }

  public function pendingReadIsAllowable(method:int):Boolean {
    return false; // was for openDocument, but now (after implement factory concept) it is read immediately (sync read)
  }

  private static var methodIdToName:Vector.<String>;

  public function describeMethod(methodId:int):String {
    if (methodIdToName == null) {
      var names:XMLList = describeType(ClientMethod).constant.@name;
      methodIdToName = new Vector.<String>(names.length(), true);
      for each (var name:String in names) {
        methodIdToName[ClientMethod[name]] = name;
      }
    }

    return methodIdToName[methodId];
  }
}
}

final class ClientMethod {
  public static const openProject:int = 0;
  public static const closeProject:int = 1;
  
  public static const registerLibrarySet:int = 2;
  public static const registerModule:int = 3;
  public static const registerDocumentFactory:int = 4;
  public static const updateDocumentFactory:int = 5;
  public static const openDocument:int = 6;
  public static const updateDocuments:int = 7;

  public static const initStringRegistry:int = 8;
  public static const updateStringRegistry:int = 9;
  public static const fillImageClassPool:int = 10;
  public static const fillSwfClassPool:int = 11;
}