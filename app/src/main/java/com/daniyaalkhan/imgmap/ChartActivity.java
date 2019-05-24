package com.daniyaalkhan.imgmap;


import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.BitmapFactory;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.provider.Settings;
import android.support.v4.app.ActivityCompat;
import android.support.v4.content.PermissionChecker;
import android.os.Bundle;
import android.util.Log;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import java.util.ArrayList;
import java.util.List;


public class ChartActivity extends Activity implements LocationListener{


    protected LocationManager locationManager;

    private TextView textView;

    private ImgMap imgMap;
    private ImageView locationPin;

    private ImageView chartView;

    private int imageWidth, imageHeight;
    private double[][] cords1, cords2;

    String[] appPermissions = {
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {

        super.onCreate(savedInstanceState);
        setContentView(R.layout.chart_activity);

        Bundle extras = getIntent().getExtras();

        this.chartView = findViewById(R.id.chartView);
        this.locationPin = findViewById(R.id.locationPin);
        this.textView = findViewById(R.id.textView);

        setChartData(extras.getInt("id"));

        imgMap = new ImgMap(cords1, cords2);
        imgMap.setScaleRes(this.imageWidth, this.imageHeight);

        /* LOCATION CODE BELOW THIS POINT */
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);

        if(PermissionChecker.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)==PackageManager.PERMISSION_GRANTED){
            locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0, 0, this);
        }else{
            checkAndRequestPermissions();
            locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0, 0, this);
        }

    }

    private void setChartData(int id){

        DBHandler db = new DBHandler(this);

        Chart chart = db.getChart(id);

        this.chartView.setImageBitmap(chart.chartBitmap);
        this.cords1 = chart.coords1;
        this.cords2 = chart.coords2;
        this.imageHeight = chart.imageHeight;
        this.imageWidth = chart.imageWidth;

    }

    @Override
    public void onLocationChanged(Location location){
        double lat=location.getLatitude(), lon=location.getLongitude();
        textView.setText("Latitude:"+lat+" Longitude:"+lon+" @"+location.getAccuracy());

        Log.i("Chart dimensions", chartView.getWidth()+" "+chartView.getHeight());
        float[] offsets = imgMap.getScaledOffsets(lat, lon, chartView.getWidth(), chartView.getHeight());
        locationPin.setX(offsets[0]-(float)25);
        locationPin.setY(offsets[1]-(float)25);

        if(location.hasBearing()) {
            locationPin.setRotation(location.getBearing());
        }
    }
    @Override
    public void onProviderDisabled(String provider) {
        Toast enableLocationToast = Toast.makeText(this, "Please enable location services", Toast.LENGTH_SHORT);
        enableLocationToast.show();
        startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS));
    }

    @Override
    public void onProviderEnabled(String provider) {
        Log.d("Latitude","enable");
    }

    @Override
    public void onStatusChanged(String provider, int status, Bundle extras) {
        Log.d("Latitude", "status");
    }

    public void checkAndRequestPermissions(){

        //Check if permissions are granted
        List<String> listPermissionsNeeded = new ArrayList<>();
        for(String perm: appPermissions){
            if(PermissionChecker.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED){
                listPermissionsNeeded.add(perm);
            }
        }

        //Ask for permissions
        if(!listPermissionsNeeded.isEmpty()){
            ActivityCompat.requestPermissions(this, listPermissionsNeeded.toArray(new String[listPermissionsNeeded.size()]), 100);
        }

        //App has all permissions
    }
    /* END LOCATION CODE*/




    class ImgMap{

        private  double latRatio, lonRatio;
        private int xRes, yRes;
        double[][] cords1,cords2;

        //Cords1 and Cords2 convention: ((Latitude, Longitude), (YPixel, XPixel))

        private ImgMap(double[][] cords1, double[][] cords2){

            //Initialize with cords1 and cords2, to calculate map scale
            this.cords1 = cords1;
            this.cords2 = cords2;

            this.latRatio = (cords2[0][0]-cords1[0][0])/(cords2[1][0]-cords1[1][0]);
            this.lonRatio = (cords2[0][1]-cords1[0][1])/(cords2[1][1]-cords1[1][1]);

        }

        //Determine lower bounds of coordinates in the image
        private double[] getImageBounds(){

            double latBound=this.cords1[0][0]-(this.latRatio*this.cords1[1][0]);
            double lonBound=this.cords2[0][1]-(this.lonRatio*this.cords2[1][1]);

            return new double[]{latBound, lonBound};

        }

        //Get Pixel offsets for given coordinates
        private float[] getOffsets(double lat, double lon){

            double[] bounds = this.getImageBounds();
            double latOffset = lat-bounds[0];
            double lonOffset = lon-bounds[1];

            double YPixel = latOffset/this.latRatio;
            double XPixel = lonOffset/this.lonRatio;

            return new float[]{(float)XPixel, (float)YPixel};

        }

        //Set pixel resolution for scaling
        private void setScaleRes(int xRes, int yRes){
            this.xRes = xRes;
            this.yRes = yRes;
        }

        //Get Equivalent offset for an image that is scaled up or down
        private float[] getScaledOffsets(double lat, double lon, double xLimit, double yLimit){

            float[] offsets = this.getOffsets(lat, lon);
            double scaledXOffset = offsets[0]*xLimit/this.xRes;
            double scaledYOffset = offsets[1]*yLimit/this.yRes;

            return new float[]{(float)scaledXOffset, (float)scaledYOffset};

        }



    }
}

/*
Pin setter code:
                float[] offsets = imgMap.getScaledOffsets(location.getLatitude(), location.getLongitude(), 1080, 1526);
                textView.setText("Latitude: "+location.getLatitude()+" Longitude: "+location.getLongitude());
                locationPin.setX(offsets[0]-15);
                locationPin.setY(offsets[1]-15);
 */
