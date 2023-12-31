public without sharing class AlertActions {
    
    public static WebLogClass wlClass = new WebLogClass();
    
    public static set<String> setPCAFcustomerTypes { set;
        get{
            if(setPCAFcustomerTypes == null){
                list<PCAF_Customer_Type__mdt>  lstPCAFcustomerTypes = [Select id, Customer_type__c, DeveloperName, MasterLabel from PCAF_Customer_Type__mdt LIMIT 100];
                System.debug('lstPCAFcustomerTypes : '+lstPCAFcustomerTypes);
                if(lstPCAFcustomerTypes.isEmpty()){
                    setPCAFcustomerTypes =  new set<String>();
                }else{
                    set<String> PCAFTypes = new set<String>();
                    setPCAFcustomerTypes = new set<String>();
                    for(PCAF_Customer_Type__mdt each : lstPCAFcustomerTypes){
                        PCAFTypes.add(each.Customer_type__c);
                    }
                    System.debug('PCAFTypes :' +PCAFTypes);
                    setPCAFcustomerTypes.addAll(PCAFTypes);
                }
            }
            
            return setPCAFcustomerTypes;
        }
    }

    public static void prepareforMCDIntegration(List<Alert__c> alertList){
        
        List<Debug__c> debugList = new List<Debug__c>();
        for(Alert__c alert: alertList){
            Debug__c log = new Debug__c();
            debugList.add(log);         
        } 
        
        Insert debugList;
        Integer i = 0;
        
        List<Web_Integration_Log__c> wiLogList = new List<Web_Integration_Log__c>();
        
        for(Alert__c alert: alertList){
            Web_Integration_Log__c wiLog = new Web_Integration_Log__c();
            wiLog.AccountId__c = alert.Prospect_Customer__c;
            wiLog.Request_Action__c = 'MaintainCustomerDetails';
            wiLog.Request_Object_Type__c = 'Account';
            wiLog.Alert__c = alert.Id; 
            wiLog.Debug_Log__c = debugList[i].Id;
            wiLogList.add(wiLog);   
            i++;            
        }
        
        Insert wiLogList;
        
        Set<Id> wiLogIds = new Set<Id>();
        for(Web_Integration_Log__c webLog: wiLogList){
            wiLogIds.add(webLog.Id);
        }
        
        If(wiLogIds.size()>0){
            SendMCDs(wiLogIds);
        }
    }

    public static boolean isPersonAccount(String strCustomerType){
        if(!setPCAFcustomerTypes.isEmpty() && setPCAFcustomerTypes.contains(strCustomerType)){
           return true;
        }
        return false;
    }
    
    @future(callout = true)
    public static void SendMCDs(Set<Id> wiLogIds){
        system.debug('---wiLogIds--'+wiLogIds);
        List<Web_Integration_Log__c> webLogs = [Select AccountId__c, AccountwithIBBId__c, ApplicantId__c, AssetRelationshipId__c, CreatedById, CreatedDate, Debug_Log__c, IsDeleted, 
                                                IntegrationTaskPerformed__c, LastModifiedById, LastModifiedDate, OpportunityId__c, OwnerId, 
                                                ConnectionReceivedId, Id, Request_Action__c, Request_Body__c, Request_Log_Date_Time__c, Request_Object_Type__c, Request_Output__c, 
                                                Request_Status__c, Response_Action__c, Response_Body__c, Response_Log_Date_Time__c, Response_Message_Name__c, Response_Object_Type__c, 
                                                Response_Output__c, Response_Status__c, ConnectionSentId, SystemModstamp, Name,Alert__c from Web_Integration_Log__c 
                                                Where Request_Action__c = 'MaintainCustomerDetails' and Id in: wiLogIds];
        
        system.debug('---webLogs--'+webLogs);
        Set<Id> alertIds = new Set<Id>();
        Set<Id> debugLogIds = new Set<Id>();
        for(Web_Integration_Log__c weblog: webLogs ) {
            alertIds.add(weblog.Alert__c);
            debugLogIds.add(weblog.Debug_Log__c);
        }
        
        Map<Id,Alert__c> alertMap = new Map<Id,Alert__c>([Select Id,Alert_Type__c, Prospect_Customer__c,Prospect_Customer__r.EBS_ID__c, Prospect_Customer__r.Customer_Type__c,
                                                            Prospect_Customer__r.SFDC_ID__c, Active__c, Vulnerable_Customer__c, Prospect_Customer__r.recordtypeID, COP_Status__c
                                                            from Alert__c Where Id in: alertIds]);
        
        Map<Id,Debug__c> debugLogMap = new Map<Id,Debug__c>([Select Id from Debug__c where Id in:debugLogIds]);
        
        Set<string> processedAccounts = new Set<string>(); 
        
        XML_Message__c xmlMessage = [Select x.Type__c, x.Start_Tag__c, x.Name, x.Id, x.End_Tag__c, 
                                     x.Element_Name__c, x.Active__c, Service_Name_Element__c,
                                     Service_Namespace__c, Element_Namespace__c, Buffered__c, 
                                     (Select Name, Field_Label__c, Field_API_Name__c, Start_Tag__c, End_Tag__c, Message_Order__c, Data_Type__c  
                                      From XML_Message_Tags__r Order By Message_Order__c ASC) 
                                     From XML_Message__c x where x.Type__c = 'Request' and x.Name = 'MaintainCustomerDetails' 
                                     and x.Active__c = true];
        
        List<XML_Message_Tag__c> tagList = xmlMessage.XML_Message_Tags__r;
        
        Map<string, string> overrideValues = new Map<string, string>();
        
        for(XML_Message_Tag__c xmltag: tagList){
            overrideValues.put(xmltag.Name,'');
        }
        
        for(Web_Integration_Log__c weblog: webLogs ) {
            if(processedAccounts.contains(weblog.AccountId__c)) continue;            
            String s= SendMCD(weblog,alertMap.get(weblog.Alert__c),debugLogMap.get(weblog.Debug_Log__c),overrideValues);
            processedAccounts.add(weblog.AccountId__c);
            system.debug('res:' + s);
        }
        
        wlClass.upsertWebLogs();
        
    }

    public class VulnerableData{
        public string Vulnerable_Mental_health;
        public string Vulnerable_Financial_literacy;
        public string Vulnerable_Financial_Difficulty;
    }


    
    public static String SendMCD(Web_Integration_Log__c weblog, Alert__c alert,Debug__c log, Map<string, string> overrideValues) {
        String processedResponse;
        
        System.debug('Account to update: ' + weblog.AccountId__c);
        
        //webLog.AccountId__c = acc.id;
        wlClass.webLogsToUpsert.add(webLog); 
        
        Map<String, String> params = new Map<String, String>();
        params.put('inWebLogId', weblog.Id);
        params.put('inId', weblog.AccountId__c);
        params.put('inObjectType', 'Account');
        params.put('inObjectResponseType', 'Account');
        params.put('inMessageType', 'Request');
        params.put('inWhichElement', 'MaintainCustomerDetails');
        params.put('inAction', 'MaintainCustomerDetails');
        params.put('inXmlMsgName', 'MaintainCustomerDetails');
        params.put('inXmlResponseMsgName', 'AddNewCustomerAllInformation');
        
        Id accRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('ProspectCustomer').getRecordTypeId();

        System.debug('accRecordTypeId : '+accRecordTypeId+' alert.Prospect_Customer__r.recordTypeId : '+alert.Prospect_Customer__r.recordTypeId);
        System.debug('alert.Active__c : '+alert.Active__c+' alert.Alert_Type__c : '+alert.Alert_Type__c);
        System.debug('alert.Prospect_Customer__r.Customer_Type__c : '+alert.Prospect_Customer__r.Customer_Type__c);
        System.debug('isPersonAccount(alert.Prospect_Customer__r.Customer_Type__c) : '+isPersonAccount(alert.Prospect_Customer__r.Customer_Type__c));
        System.debug('alert.Vulnerable_Customer__c : '+alert.Vulnerable_Customer__c);
        
        if(alert.Prospect_Customer__r.recordTypeId == accRecordTypeId && isPersonAccount(alert.Prospect_Customer__r.Customer_Type__c)){
            //if(alert.Active__c && alert.Alert_Type__c == 'Vulnerable Customer' && isPersonAccount(alert.Prospect_Customer__r.Customer_Type__c)){
            if(alert.Active__c && alert.Alert_Type__c == 'Vulnerable Customer'){
                VulnerableData objVulnerableData = new VulnerableData();
                if(alert.Vulnerable_Customer__c.contains( 'Mental health')){
                    objVulnerableData.Vulnerable_Mental_health = 'Y';
                }else{objVulnerableData.Vulnerable_Mental_health = 'N';}

                if(alert.Vulnerable_Customer__c.contains( 'Financial literacy')){
                   objVulnerableData.Vulnerable_Financial_literacy = 'Y';
                }else{objVulnerableData.Vulnerable_Financial_literacy = 'N';}

                if(alert.Vulnerable_Customer__c.contains( 'Financial Difficulty')){
                    objVulnerableData.Vulnerable_Financial_Difficulty = 'Y';
                }else{objVulnerableData.Vulnerable_Financial_Difficulty = 'N';}
                String spare1 = JSON.serialize(objVulnerableData);
                System.debug('spare1 : '+spare1);
                overrideValues.put('Spare1', spare1);
            }
        }else{
            if(alert.Active__c && alert.Alert_Type__c == 'Vulnerable Customer' && alert.Vulnerable_Customer__c.contains( 'Financial Difficulty')) {
                overrideValues.put('Spare1', 'Vulnerable Customer-Y');          
            } else {
                overrideValues.put('Spare1', 'Vulnerable Customer-N');
            } 
            System.debug('overrideValues.get(Spare1) : '+overrideValues.get('Spare1'));
        }

        if(alert.Active__c && alert.Alert_Type__c == 'COP'){
            if(alert.COP_Status__c == true){
                overrideValues.put('Spare2', 'COP Flag Y');
            }else{
                overrideValues.put('Spare2', 'COP Flag N');
            }
        }

                     
        
        overrideValues.put('CustNo', alert.Prospect_Customer__r.EBS_ID__c);
        overrideValues.put('SFDCID', alert.Prospect_Customer__r.SFDC_ID__c);
        
        String returnString = WebServiceClass.sendRequest(params, wlClass, overrideValues, log);
        System.debug('UpdateEBSCustomer: Response - '  + returnString);
        if (returnString != null){
            processedResponse = OpportunityTriggerMethods.getStatusFromXML(returnString);
        }
        
        System.debug('*** -- processedResponse = ' + processedResponse + ' -- ***');
        if ('FAILED'.equalsIgnoreCase(processedResponse))
        {
            System.debug('*** -- MAINTAIN CUSTOMER DETAILS FAILED -- ***');
            System.debug('*** -- '+returnString +' -- ***');
            //TODO: What to do in the event of a failure
        }
        else if ('BUFFERED'.equalsIgnoreCase(processedResponse))
        {
            System.debug('*** -- MAINTAIN CUSTOMER DETAILS BUFFERED -- ***');
            System.debug('*** -- '+returnString +' -- ***');
        }   
        
        return processedResponse;
        
    }
}