﻿#Installation du module Active Directory (si ça n'est pas déjà fait)
Install-WindowsFeature -Name RSAT-AD-PowerShell


#Importer les utilisateurs à créer   
$csvFile = "users.csv" 
$users = Import-Csv  -Path $csvFile -Delimiter '|'

#Analyser les données, le nombre d'utilisateurs, combien par pays, combien occupe tel ou tel poste etc. 
$totalUser = $users.Count
$userPerCountries = $users | Group-Object Country | Sort-Object Count -Descending
$userPerPosition = $users | Group-Object Position | Sort-Object Count -Descending

#Affichage des résultats
Write-Host "Nombre total d'utilisateurs : $totalUser"
$userPerCountries | ForEach-Object { 
    Write-Host "Pays : $($_.Name) --> Nombre d'utilisateurs : $($_.Count)" 
}
$userPerPosition | ForEach-Object {
    Write-Host "Poste : $($_.Name) --> Nombre : $($_.Count)"
}

# Le script doit intégrer une gestion d'erreur et une historisation de celle-ci dans un fichier dédié 
# Créer un fichier de log pour les erreurs
$logErrorFile = "C:\Logs\error_log.txt"

#Vérifier si le fichier de log existe
if (-not (Test-Path $logErrorFile)) {
    "Début du log - $(Get-Date)" | Out-File -FilePath $logErrorFile
}

#Fonction pour ajouter les erreurs dans le log
function Write-ErrorLog {
    param (
        [string]$errorMessage
    )
    
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $errorMessage"
    $logMessage | Add-Content -Path $logErrorFile
}

#Créer un fichier de log pour les utilisateurs créés
#qui contient pour chaque utilisateur, son nom et son id, le distingueshName et la date de la création
$logFile = "C:\Logs\user_creation_log.txt"

#Vérifier si le fichier de log existe
if (-not (Test-Path $logFile)) {
    "Début du log - $(Get-Date)" | Out-File -FilePath $logFile
}
#Fonction pour ajouter les users dans le log
function Write-UserLog {
    param (
        [string]$username,
        [string]$userid,
        [string]$distinguishedName
    )
    
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Nom: $username, ID: $userid, DistinguishedName: $distinguishedName"
    $logMessage | Add-Content -Path $logFile
}


#Créer un script qui permet de créer l'arborescence comme tel : une OU pour chaque pays et dans chaque pays créer une OU par poste
#Racine de mon AD
$basePath = "DC=scripting,DC=local" 

#Boucle foreach qui parcour tous les pays
foreach ($country in $userPerCountries) {
    try {
        #Chemin de l'OU du pays
        $countryOUPath = "OU=$($country.Name),$basePath"

        #Si l'OU du pays n'existe pas, on la crée
        if (-not (Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $countryOUPath })) {
            New-ADOrganizationalUnit -Name $country.Name -Path $basePath
        }        

        foreach ($position in $userPerPosition) {
            #Chemin de l'OU du poste
            $positionOUPath = "OU=$($position.Name),$countryOUPath"

            #Si l'OU du poste n'existe pas, on la crée
            if (-not (Get-ADOrganizationalUnit -Filter { Name -eq $position.Name })) {
                New-ADOrganizationalUnit -Name $position.Name -Path $positionOUPath
            }
        }
    }
    catch {
        Write-ErrorLog -errorMessage "Erreur lors de la création de l'OU pour le pays $($country.Name) : $_"
    }


}



# Créer un second script permettant de peupler automatiquement les bonnes OU avec les bons utilisateurs, le script doit également 
#Boucle qui parcour tous les utilisateurs
foreach ($user in $users) {
    $userid = $user.Name + "." + $user.ID
    $username = $user.Name
    $userposition = $user.Position
    $usercountry = $user.Country
    $OUPath = "OU=$userposition,OU=$usercountry,$basePath"

    #Vérifier si l'utilisateur existe déjà
    if (Get-ADUser -Filter "SamAccountName -eq '$userid'" -ErrorAction SilentlyContinue) {
        Write-Host "L'utilisateur $userid existe déjà."
        continue #On passe à l'utilisateur suivant
    }

    try {
        New-ADUser -Name "$username" `
            -SamAccountName $userid `
            -Surname "" `
            -UserPrincipalName "$username@scripting.com" `
            -Enabled $true `
            -AccountPassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force) `
            -Path $OUPath

        $user = Get-ADUser -SamAccountName $userid
        Write-UserLog -username $username -userid $userid -distinguishedName $user.DistinguishedName
    }
    catch {
        Write-ErrorLog -errorMessage "Erreur lors de la création de l'utilisateur $username : $_"
    }

}