"""Generate a dependency-free Xcode project with a local Swift package and XCTest targets.
Run from any directory: python3 工具/生成工程.py
"""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = '菠萝单词'
objects = {}

def ident(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

class Ref(str):
    pass

def reference(label):
    return Ref(ident(label))

def add(label, isa, **fields):
    key = ident(label)
    objects[key] = {'isa': isa, **fields}
    return Ref(key)

def render(value, indent=0):
    if isinstance(value, Ref):
        return str(value)
    if isinstance(value, dict):
        inner = '\n'.join('\t' * (indent+1) + json.dumps(str(k), ensure_ascii=False) + ' = ' + render(v, indent+1) + ';' for k,v in value.items())
        return '{\n' + inner + '\n' + '\t' * indent + '}'
    if isinstance(value, (list,tuple)):
        return '(' + ', '.join(render(x,indent) for x in value) + (',' if value else '') + ')'
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)

def file_ref(path, kind):
    return add('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

app_files = [p.relative_to(ROOT).as_posix() for p in sorted((ROOT/'PineappleWords').rglob('*.swift'))]
unit_files = [p.relative_to(ROOT).as_posix() for base in ['Tests/PineappleCoreTests','PineappleWordsTests'] for p in sorted((ROOT/base).rglob('*.swift'))]
ui_files = [p.relative_to(ROOT).as_posix() for p in sorted((ROOT/'PineappleWordsUITests').rglob('*.swift'))]
source_groups = []
source_phases = {}
for name, paths in [('App', app_files), ('Unit', unit_files), ('UI', ui_files)]:
    refs, builds = [], []
    for path in paths:
        ref = file_ref(path, 'sourcecode.swift'); refs.append(ref)
        builds.append(add('build:' + name + ':' + path, 'PBXBuildFile', fileRef=ref))
    source_groups.append(add('group:' + name, 'PBXGroup', children=refs, name={'App':'App 源码','Unit':'单元测试','UI':'界面测试'}[name], sourceTree='<group>'))
    source_phases[name] = add('sources:' + name, 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)

asset_ref = file_ref('PineappleWords/Resources/Assets.xcassets', 'folder.assetcatalog')
privacy_ref = file_ref('PineappleWords/Resources/PrivacyInfo.xcprivacy', 'text.xml')
info_ref = file_ref('PineappleWords/Info.plist', 'text.plist.xml')
resources = add('resources:App', 'PBXResourcesBuildPhase', buildActionMask=2147483647,
    files=[add('build:assets','PBXBuildFile',fileRef=asset_ref),add('build:privacy','PBXBuildFile',fileRef=privacy_ref)],runOnlyForDeploymentPostprocessing=0)
resource_group = add('group:resources', 'PBXGroup',children=[asset_ref,privacy_ref,info_ref],name='资源',sourceTree='<group>')

package_ref = add('package:local', 'XCLocalSwiftPackageReference', relativePath='.')
packages = {}
frameworks = {}
for target in ['App','Unit','UI']:
    deps=[]
    if target != 'UI':
        packages[target] = add('package-product:'+target,'XCSwiftPackageProductDependency',package=package_ref,productName='PineappleCore')
        deps=[add('package-build:'+target,'PBXBuildFile',productRef=packages[target])]
    frameworks[target]=add('frameworks:'+target,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=deps,runOnlyForDeploymentPostprocessing=0)

product_refs = {}
for target,name,kind in [('App','PineappleWords.app','wrapper.application'),('Unit','PineappleWordsTests.xctest','wrapper.cfbundle'),('UI','PineappleWordsUITests.xctest','wrapper.cfbundle')]:
    product_refs[target]=add('product:'+target,'PBXFileReference',explicitFileType=kind,includeInIndex=0,path=name,sourceTree='BUILT_PRODUCTS_DIR')
products_group=add('group:products','PBXGroup',children=list(product_refs.values()),name='Products',sourceTree='<group>')
doc_refs=[file_ref(p,'net.daringfireball.markdown') for p in ['README.md','开发说明.md','测试与验收.md']]
doc_group=add('group:docs','PBXGroup',children=doc_refs,name='中文说明',sourceTree='<group>')
main_group=add('group:main','PBXGroup',children=source_groups+[resource_group,doc_group,products_group],sourceTree='<group>')

def config_list(label, settings):
    configs=[]
    for name in ['Debug','Release']:
        values=dict(settings)
        if label == 'project':
            values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O',
                           'DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym',
                           'ENABLE_TESTABILITY':'YES' if name=='Debug' else 'NO',
                           'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)' if name=='Debug' else '$(inherited)'})
        configs.append(add('config:'+label+':'+name,'XCBuildConfiguration',buildSettings=values,name=name))
    return add('config-list:'+label,'XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

project_config=config_list('project',{
    'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES',
    'CLANG_WARN_BOOL_CONVERSION':'YES','CLANG_WARN_CONSTANT_CONVERSION':'YES','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES',
    'CLANG_WARN_UNREACHABLE_CODE':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','GCC_NO_COMMON_BLOCKS':'YES',
    'GCC_WARN_64_TO_32_BIT_CONVERSION':'YES','GCC_WARN_UNDECLARED_SELECTOR':'YES',
    'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0',
    'SWIFT_STRICT_CONCURRENCY':'targeted','SWIFT_EMIT_LOC_STRINGS':'YES'
})
common={'CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'','TARGETED_DEVICE_FAMILY':'1,2',
    'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO',
    'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],
    'PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'5.0'}
app_config=config_list('App',{**common,'PRODUCT_BUNDLE_IDENTIFIER':'personal.pineapplewords',
    'INFOPLIST_FILE':'PineappleWords/Info.plist','INFOPLIST_KEY_UILaunchScreen_Generation':'YES',
    'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor',
    'CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0.0'})
unit_config=config_list('Unit',{**common,'PRODUCT_BUNDLE_IDENTIFIER':'personal.pineapplewords.tests',
    'BUNDLE_LOADER':'$(TEST_HOST)','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/PineappleWords.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PineappleWords'})
ui_config=config_list('UI',{**common,'PRODUCT_BUNDLE_IDENTIFIER':'personal.pineapplewords.uitests',
    'TEST_TARGET_NAME':'PineappleWords'})
target_names={'App':'PineappleWords','Unit':'PineappleWordsTests','UI':'PineappleWordsUITests'}
for target,configuration in [('App',app_config),('Unit',unit_config),('UI',ui_config)]:
    dependencies=[]
    if target!='App':
        proxy=add('proxy:'+target,'PBXContainerItemProxy',containerPortal=reference('project'),proxyType=1,remoteGlobalIDString=reference('target:App'),remoteInfo='PineappleWords')
        dependencies=[add('dependency:'+target,'PBXTargetDependency',target=reference('target:App'),targetProxy=proxy)]
    phases=[source_phases[target],frameworks[target]]
    if target=='App': phases.append(resources)
    add('target:'+target,'PBXNativeTarget',buildConfigurationList=configuration,buildPhases=phases,buildRules=[],dependencies=dependencies,
        name=target_names[target],productName=target_names[target],productReference=product_refs[target],
        packageProductDependencies=[packages[target]] if target in packages else [],
        productType='com.apple.product-type.application' if target=='App' else ('com.apple.product-type.bundle.unit-test' if target=='Unit' else 'com.apple.product-type.bundle.ui-testing'))

add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600',
    'TargetAttributes':{str(reference('target:App')):{'CreatedOnToolsVersion':'16.0'},
                        str(reference('target:Unit')):{'CreatedOnToolsVersion':'16.0','TestTargetID':reference('target:App')},
                        str(reference('target:UI')):{'CreatedOnToolsVersion':'16.0','TestTargetID':reference('target:App')}}},
    buildConfigurationList=project_config,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,
    knownRegions=['zh-Hans','en','Base'],mainGroup=main_group,productRefGroup=products_group,
    projectDirPath='',projectRoot='',packageReferences=[package_ref],targets=[reference('target:'+x) for x in target_names])

project_dir=ROOT/(PROJECT_NAME+'.xcodeproj'); project_dir.mkdir(exist_ok=True)
project={'archiveVersion':1,'classes':{},'objectVersion':60,'objects':objects,'rootObject':reference('project')}
(project_dir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render(project)+'\n',encoding='utf8',newline='\n')
workspace=project_dir/'project.xcworkspace'; workspace.mkdir(exist_ok=True)
(workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n',encoding='utf8')
scheme=ET.Element('Scheme',{'LastUpgradeVersion':'1600','version':'1.3'})
build=ET.SubElement(scheme,'BuildAction',{'parallelizeBuildables':'YES','buildImplicitDependencies':'YES'})
entries=ET.SubElement(build,'BuildActionEntries')
def buildable(parent,target):
    ET.SubElement(parent,'BuildableReference',{'BuildableIdentifier':'primary','BlueprintIdentifier':ident('target:'+target),
        'BuildableName':target_names[target]+('.app' if target=='App' else '.xctest'),
        'BlueprintName':target_names[target],'ReferencedContainer':'container:'+PROJECT_NAME+'.xcodeproj'})
entry=ET.SubElement(entries,'BuildActionEntry',{'buildForTesting':'YES','buildForRunning':'YES','buildForProfiling':'YES','buildForArchiving':'YES','buildForAnalyzing':'YES'})
buildable(entry,'App')
test=ET.SubElement(scheme,'TestAction',{'buildConfiguration':'Debug','selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB',
    'selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','shouldUseLaunchSchemeArgsEnv':'YES','codeCoverageEnabled':'YES'})
testables=ET.SubElement(test,'Testables')
for target in ['Unit','UI']:
    item=ET.SubElement(testables,'TestableReference',{'skipped':'NO','parallelizable':'NO'}); buildable(item,target)
launch=ET.SubElement(scheme,'LaunchAction',{'buildConfiguration':'Debug','selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB',
    'selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','launchStyle':'0','useCustomWorkingDirectory':'NO',
    'ignoresPersistentStateOnLaunch':'NO','debugDocumentVersioning':'YES','debugServiceExtension':'internal','allowLocationSimulation':'YES'})
run=ET.SubElement(launch,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}); buildable(run,'App')
profile=ET.SubElement(scheme,'ProfileAction',{'buildConfiguration':'Release','shouldUseLaunchSchemeArgsEnv':'YES','savedToolIdentifier':'','useCustomWorkingDirectory':'NO','debugDocumentVersioning':'YES'})
buildable(ET.SubElement(profile,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}),'App')
ET.SubElement(scheme,'AnalyzeAction',{'buildConfiguration':'Debug'})
ET.SubElement(scheme,'ArchiveAction',{'buildConfiguration':'Release','revealArchiveInOrganizer':'YES'})
scheme_dir=project_dir/'xcshareddata'/'xcschemes'; scheme_dir.mkdir(parents=True,exist_ok=True)
ET.indent(scheme,space='  ')
ET.ElementTree(scheme).write(scheme_dir/(PROJECT_NAME+'.xcscheme'),encoding='utf-8',xml_declaration=True)

info={'CFBundleDisplayName':'菠萝单词','CFBundleDevelopmentRegion':'zh-Hans','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)',
      'CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL',
      'CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)',
      'LSRequiresIPhoneOS':True,'ITSAppUsesNonExemptEncryption':False,'UIRequiresFullScreen':False,
      'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},
      'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
      'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']}
with (ROOT/'PineappleWords/Info.plist').open('wb') as file: plistlib.dump(info,file,sort_keys=False)
resources_dir=ROOT/'PineappleWords/Resources'; resources_dir.mkdir(parents=True,exist_ok=True)
privacy={'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],
         'NSPrivacyCollectedDataTypes':[{'NSPrivacyCollectedDataType':'NSPrivacyCollectedDataTypeOtherUserContent',
                                        'NSPrivacyCollectedDataTypeLinked':True,'NSPrivacyCollectedDataTypeTracking':False,
                                        'NSPrivacyCollectedDataTypePurposes':['NSPrivacyCollectedDataTypePurposeAppFunctionality']}],
         'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryFileTimestamp','NSPrivacyAccessedAPITypeReasons':['C617.1']}]}
with (resources_dir/'PrivacyInfo.xcprivacy').open('wb') as file: plistlib.dump(privacy,file)

def validate_references(value):
    if isinstance(value,Ref):
        assert value in objects, 'Missing reference: '+value
    elif isinstance(value,dict):
        for v in value.values(): validate_references(v)
    elif isinstance(value,list):
        for v in value: validate_references(v)
validate_references(project)
for path in app_files+unit_files+ui_files:
    assert (ROOT/path).exists()
print(json.dumps({'app_sources':len(app_files),'unit_sources':len(unit_files),'ui_sources':len(ui_files),
                  'project_objects':len(objects),'reference_validation':'passed'},ensure_ascii=False,indent=2))
