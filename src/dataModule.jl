module DataModule

using XLSX
using DateFrames

function load_and_clean()
  file = "data/data/Draft Data sheet.xlsx"   
end
data = XLSX.readtable(file, 1)
df = DataFrames(data)

# Cleaning operation go here

return df
end
function validate_data(df)
    #validate operation go here 

    return true 
end

end






